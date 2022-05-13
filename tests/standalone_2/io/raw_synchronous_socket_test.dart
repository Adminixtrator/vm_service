// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import "dart:async";
import "dart:io";
import "dart:isolate";
import "dart:math";

import "package:async_helper/async_helper.dart";
import "package:expect/expect.dart";

const String loopbackIPv4String = "127.0.0.1";

void testArguments() {
  Expect.throws(() => RawSynchronousSocket.connectSync(null, 0));
  Expect
      .throws(() => RawSynchronousSocket.connectSync(loopbackIPv4String, null));
  Expect.throws(
      () => RawSynchronousSocket.connectSync(loopbackIPv4String, 65536));
  Expect.throws(() => RawSynchronousSocket.connectSync(loopbackIPv4String, -1));
}

// The connection attempt happens on the main Dart thread and the OS timeout can
// be arbitrarily long, causing timeout issues on the build bots. This isn't an
// issue with the async sockets since the lookup for a connect call happens on
// the IO service thread.
/*
void testInvalidConnect() {
  // Connect to an unknown DNS name.
  try {
    var socket = RawSynchronousSocket.connectSync("ko.faar.__hest__", 0);
    Expect.fail("Failure expected");
  } catch (e) {
    Expect.isTrue(e is SocketException);
  }

  // Connect to an unavaliable IP-address.
  try {
    var socket = RawSynchronousSocket.connectSync("1.2.3.4", 0);
    Expect.fail("Failure expected");
  } catch (e) {
    Expect.isTrue(e is SocketException);
  }
}
*/

void testSimpleConnect() {
  asyncStart();
  RawServerSocket.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    var socket =
        RawSynchronousSocket.connectSync(loopbackIPv4String, server.port);
    server.listen((serverSocket) {
      Expect.equals(socket.address, serverSocket.remoteAddress);
      Expect.equals(socket.port, serverSocket.remotePort);
      Expect.equals(socket.remoteAddress, server.address);
      Expect.equals(socket.remotePort, server.port);
      socket.closeSync();
      server.close();
      asyncEnd();
    });
  });
}

void testServerListenAfterConnect() {
  asyncStart();
  RawServerSocket.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    Expect.isTrue(server.port > 0);
    var client =
        RawSynchronousSocket.connectSync(loopbackIPv4String, server.port);
    server.listen((socket) {
      client.closeSync();
      server.close();
      socket.close();
      asyncEnd();
    });
  });
}

const messageSize = 1000;
// Configuration fields for the EchoServer.
enum EchoServerTypes {
  // Max accumulated connections to server before close. Defaults to 1.
  CONNECTION_COUNT,
  // Sets the range of the fields to check in the list generated by
  // createTestData().
  OFFSET_END,
  OFFSET_START,
  // The port used to communicate with an isolate.
  ISOLATE_SEND_PORT,
  // The port of the newly created echo server.
  SERVER_PORT
}

List<int> createTestData() {
  return new List<int>.generate(messageSize, (index) => index & 0xff);
}

// Consumes data generated by a test and compares it against the original test
// data. The optional fields, start and end, are used to compare against
// segments of the original test data list. In other words, data.length == (end
// - start).
void verifyTestData(List<int> data, [int start = 0, int end]) {
  assert(data != null);
  List<int> expected = createTestData();
  if (end == null) {
    end = data.length;
  }
  end = min(messageSize, end);
  Expect.equals(end - start, data.length);
  for (int i = 0; i < (end - start); i++) {
    Expect.equals(expected[start + i], data[i]);
  }
}

// The echo server is spawned in a new isolate and is used to test various
// synchronous read/write operations by echoing any data received back to the
// sender. The server should shutdown automatically after a specified number of
// socket disconnections (default: 1).
Future echoServer(var sendPort) async {
  RawServerSocket.bind(InternetAddress.loopbackIPv4, 0).then((server) async {
    ReceivePort receivePort = new ReceivePort();
    Map response = {
      EchoServerTypes.ISOLATE_SEND_PORT: receivePort.sendPort,
      EchoServerTypes.SERVER_PORT: server.port
    };
    sendPort.send(response);
    Map limits = await receivePort.first;
    int start = limits[EchoServerTypes.OFFSET_START];
    int end = limits[EchoServerTypes.OFFSET_END];
    int length = end - start;
    int connection_count = limits[EchoServerTypes.CONNECTION_COUNT] ?? 1;
    int connections = 0;
    sendPort = limits[EchoServerTypes.ISOLATE_SEND_PORT];
    server.listen((client) {
      int bytesRead = 0;
      int bytesWritten = 0;
      bool closedEventReceived = false;
      List<int> data = new List<int>(length);
      client.writeEventsEnabled = false;
      client.listen((event) {
        switch (event) {
          case RawSocketEvent.read:
            Expect.isTrue(bytesWritten == 0);
            Expect.isTrue(client.available() > 0);
            var buffer = client.read(client.available());
            data.setRange(bytesRead, bytesRead + buffer.length, buffer);
            bytesRead += buffer.length;
            // Once we've read all the data, we can echo it back. Otherwise,
            // keep waiting for more bytes.
            if (bytesRead >= length) {
              verifyTestData(data, start, end);
              client.writeEventsEnabled = true;
            }
            break;
          case RawSocketEvent.write:
            Expect.isFalse(client.writeEventsEnabled);
            bytesWritten +=
                client.write(data, bytesWritten, data.length - bytesWritten);
            if (bytesWritten < length) {
              client.writeEventsEnabled = true;
            } else if (bytesWritten == length) {
              // Close the socket for writing from the server since we're done
              // writing to this socket. The connection is closed completely
              // after the client closes the socket for reading from the server.
              client.shutdown(SocketDirection.send);
            }
            break;
          case RawSocketEvent.readClosed:
            client.close();
            break;
          case RawSocketEvent.closed:
            Expect.isFalse(closedEventReceived);
            closedEventReceived = true;
            break;
          default:
            throw "Unexpected event $event";
        }
      }, onDone: () {
        Expect.isTrue(closedEventReceived);
        connections++;
        if (connections >= connection_count) {
          server.close();
        }
      });
    }, onDone: () {
      // Let the client know we're shutting down then kill the isolate.
      sendPort.send(null);
      Isolate.current.kill();
    });
  });
}

Future testSimpleReadWrite({bool dropReads}) async {
  asyncStart();
  // This test creates a server and a client connects. The client writes data
  // to the socket and the server echos it back. The client confirms the data it
  // reads is the same as the data sent, then closes the socket, resulting in
  // the closing of the server, which responds on receivePort with null to
  // specify the echo server isolate is about to be killed. If an error occurs
  // in the echo server, the exception and stack trace are sent to receivePort,
  // which prints the exception and stack trace before eventually throwing an
  // error.
  ReceivePort receivePort = new ReceivePort();
  Isolate echo = await Isolate.spawn(echoServer, receivePort.sendPort);

  Map response = await receivePort.first;
  SendPort sendPort = response[EchoServerTypes.ISOLATE_SEND_PORT];
  int serverInternetPort = response[EchoServerTypes.SERVER_PORT];

  receivePort = new ReceivePort();
  echo.addErrorListener(receivePort.sendPort);

  Map limits = {
    EchoServerTypes.OFFSET_START: 0,
    EchoServerTypes.OFFSET_END: messageSize,
    EchoServerTypes.ISOLATE_SEND_PORT: receivePort.sendPort
  };
  sendPort.send(limits);

  try {
    var socket = RawSynchronousSocket.connectSync(
        loopbackIPv4String, serverInternetPort);
    List<int> data = createTestData();
    socket.writeFromSync(data);
    List<int> result = socket.readSync(data.length);
    verifyTestData(result);
    socket.shutdown(SocketDirection.send);
    socket.closeSync();
  } catch (e, stack) {
    print("Echo test failed in the client");
    rethrow;
  }
  // Wait for the server to shutdown before finishing the test.
  var result = await receivePort.first;
  if (result != null) {
    throw "Echo test failed in server!\nError: ${result[0]}\nStack trace:" +
        " ${result[1]}";
  }
  asyncEnd();
}

Future testPartialRead() async {
  asyncStart();
  // This test is based on testSimpleReadWrite, but instead of reading the
  // entire echoed message at once, it reads it in two calls to readIntoSync.
  ReceivePort receivePort = new ReceivePort();
  Isolate echo = await Isolate.spawn(echoServer, receivePort.sendPort);

  Map response = await receivePort.first;
  SendPort sendPort = response[EchoServerTypes.ISOLATE_SEND_PORT];
  int serverInternetPort = response[EchoServerTypes.SERVER_PORT];
  List<int> data = createTestData();

  receivePort = new ReceivePort();
  echo.addErrorListener(receivePort.sendPort);

  Map limits = {
    EchoServerTypes.OFFSET_START: 0,
    EchoServerTypes.OFFSET_END: 1000,
    EchoServerTypes.ISOLATE_SEND_PORT: receivePort.sendPort
  };
  sendPort.send(limits);

  try {
    var socket = RawSynchronousSocket.connectSync(
        loopbackIPv4String, serverInternetPort);
    int half_length = (data.length / 2).toInt();

    // Send the full data list to the server.
    socket.writeFromSync(data);
    List<int> result = new List<int>(data.length);

    // Read half at a time and check that there's still more bytes available.
    socket.readIntoSync(result, 0, half_length);
    verifyTestData(result.sublist(0, half_length), 0, half_length);
    Expect.isTrue(socket.available() == (data.length - half_length));

    // Read the second half and verify again.
    socket.readIntoSync(result, half_length);
    verifyTestData(result);
    Expect.isTrue(socket.available() == 0);

    socket.closeSync();
  } catch (e, stack) {
    print("Echo test failed in the client.");
    rethrow;
  }
  // Wait for the server to shutdown before finishing the test.
  var result = await receivePort.first;
  if (result != null) {
    throw "Echo test failed in server!\nError: ${result[0]}\nStack trace:" +
        " ${result[1]}";
  }
  asyncEnd();
}

Future testPartialWrite() async {
  asyncStart();
  // This test is based on testSimpleReadWrite, but instead of writing the
  // entire data buffer at once, it writes different parts of the buffer over
  // multiple calls to writeFromSync.
  ReceivePort receivePort = new ReceivePort();
  Isolate echo = await Isolate.spawn(echoServer, receivePort.sendPort);

  Map response = await receivePort.first;
  List<int> data = createTestData();
  SendPort sendPort = response[EchoServerTypes.ISOLATE_SEND_PORT];
  int startOffset = 32;
  int endOffset = (data.length / 2).toInt();
  int serverInternetPort = response[EchoServerTypes.SERVER_PORT];

  receivePort = new ReceivePort();
  echo.addErrorListener(receivePort.sendPort);

  Map limits = {
    EchoServerTypes.OFFSET_START: startOffset,
    EchoServerTypes.OFFSET_END: endOffset,
    EchoServerTypes.ISOLATE_SEND_PORT: receivePort.sendPort
  };
  sendPort.send(limits);
  try {
    var socket = RawSynchronousSocket.connectSync(
        loopbackIPv4String, serverInternetPort);
    List<int> data = createTestData();

    // Write a subset of data to the server.
    socket.writeFromSync(data, startOffset, endOffset);

    // Grab the response and verify it's correct.
    List<int> result = new List<int>(endOffset - startOffset);
    socket.readIntoSync(result);

    Expect.equals(result.length, endOffset - startOffset);
    verifyTestData(result, startOffset, endOffset);
    socket.closeSync();
  } catch (e, stack) {
    print("Echo test failed in the client.");
    rethrow;
  }

  // Wait for the server to shutdown before finishing the test.
  var result = await receivePort.first;
  if (result != null) {
    throw "Echo test failed in server!\nError: ${result[0]}\nStack trace:" +
        " ${result[1]}";
  }
  asyncEnd();
}

Future testShutdown() async {
  asyncStart();
  // This test creates a server and a client connects. The client then tries to
  // perform various operations after being shutdown in a specific direction, to
  // ensure reads or writes cannot be performed if the socket has been shutdown
  // for reading or writing.
  ReceivePort receivePort = new ReceivePort();
  Isolate echo = await Isolate.spawn(echoServer, receivePort.sendPort);

  Map response = await receivePort.first;
  SendPort sendPort = response[EchoServerTypes.ISOLATE_SEND_PORT];
  int serverInternetPort = response[EchoServerTypes.SERVER_PORT];
  List<int> data = createTestData();

  receivePort = new ReceivePort();
  echo.addErrorListener(receivePort.sendPort);

  Map limits = {
    EchoServerTypes.OFFSET_START: 0,
    EchoServerTypes.OFFSET_END: data.length,
    EchoServerTypes.ISOLATE_SEND_PORT: receivePort.sendPort,
    // Tell the server to shutdown after 3 sockets disconnect.
    EchoServerTypes.CONNECTION_COUNT: 3
  };
  sendPort.send(limits);

  try {
    var socket = RawSynchronousSocket.connectSync(
        loopbackIPv4String, serverInternetPort);

    // Close from both directions. Shouldn't be able to read/write to the
    // socket.
    socket.shutdown(SocketDirection.both);
    Expect.throws(
        () => socket.writeFromSync(data), (e) => e is SocketException);
    Expect.throws(
        () => socket.readSync(data.length), (e) => e is SocketException);
    socket.closeSync();

    // Close the socket for reading then try and perform a read. This should
    // cause a SocketException.
    socket = RawSynchronousSocket.connectSync(
        loopbackIPv4String, serverInternetPort);
    socket.shutdown(SocketDirection.receive);
    // Throws exception when the socket is closed for RECEIVE.
    Expect.throws(
        () => socket.readSync(data.length), (e) => e is SocketException);
    socket.closeSync();

    // Close the socket for writing and try to do a write. This should cause an
    // OSError to be throw as the pipe is closed for writing.
    socket = RawSynchronousSocket.connectSync(
        loopbackIPv4String, serverInternetPort);
    socket.shutdown(SocketDirection.send);
    Expect.throws(
        () => socket.writeFromSync(data), (e) => e is SocketException);
    socket.closeSync();
  } catch (e, stack) {
    print("Echo test failed in client.");
    rethrow;
  }
  // Wait for the server to shutdown before finishing the test.
  var result = await receivePort.first;
  if (result != null) {
    throw "Echo test failed in server!\nError: ${result[0]}\nStack trace:" +
        " ${result[1]}";
  }
  asyncEnd();
}

Future testInvalidReadWriteOperations() {
  asyncStart();
  RawServerSocket.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    server.listen((socket) {});
    List<int> data = createTestData();
    var socket =
        RawSynchronousSocket.connectSync(loopbackIPv4String, server.port);

    // Invalid writeFromSync invocations
    Expect.throwsRangeError(() => socket.writeFromSync(data, data.length + 1));
    Expect
        .throwsRangeError(() => socket.writeFromSync(data, 0, data.length + 1));
    Expect.throwsRangeError(() => socket.writeFromSync(data, 1, 0));
    Expect.throwsArgumentError(() => socket.writeFromSync(data, null));

    // Invalid readIntoSync invocations
    List<int> buffer = new List<int>(10);
    Expect
        .throwsRangeError(() => socket.readIntoSync(buffer, buffer.length + 1));
    Expect.throwsRangeError(
        () => socket.readIntoSync(buffer, 0, buffer.length + 1));
    Expect.throwsRangeError(() => socket.readIntoSync(buffer, 1, 0));
    Expect.throwsArgumentError(() => socket.readIntoSync(buffer, null));

    // Invalid readSync invocation
    Expect.throwsArgumentError(() => socket.readSync(-1));

    server.close();
    socket.closeSync();
    asyncEnd();
  });
}

void testClosedError() {
  asyncStart();
  RawServerSocket.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    server.listen((socket) {
      socket.close();
    });
    var socket =
        RawSynchronousSocket.connectSync(loopbackIPv4String, server.port);
    server.close();
    socket.closeSync();
    Expect.throws(() => socket.remotePort, (e) => e is SocketException);
    Expect.throws(() => socket.remoteAddress, (e) => e is SocketException);
    asyncEnd();
  });
}

main() async {
  asyncStart();
  testArguments();
  // testInvalidConnect(); Long timeout for bad lookups, so disable for bots.
  await testShutdown();
  testSimpleConnect();
  testServerListenAfterConnect();
  await testSimpleReadWrite();
  await testPartialRead();
  await testPartialWrite();
  testInvalidReadWriteOperations();
  testClosedError();
  asyncEnd();
}