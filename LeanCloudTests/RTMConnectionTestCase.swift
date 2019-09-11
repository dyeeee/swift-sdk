//
//  RTMConnectionTestCase.swift
//  LeanCloudTests
//
//  Created by zapcannon87 on 2018/11/3.
//  Copyright © 2018 LeanCloud. All rights reserved.
//

import XCTest
@testable import LeanCloud

class RTMConnectionTestCase: RTMBaseTestCase {
    
    override func setUp() {
        super.setUp()
        RTMConnectionManager.default.protobuf1Map.removeAll()
        RTMConnectionManager.default.protobuf3Map.removeAll()
    }
    
    override func tearDown() {
        RTMConnectionManager.default.protobuf1Map.removeAll()
        RTMConnectionManager.default.protobuf3Map.removeAll()
        super.tearDown()
    }
    
    func testConnectionReference() {
        let application = try! LCApplication(id: uuid, key: uuid)
        for imProtocol in
            [RTMConnection.LCIMProtocol.protobuf1,
             RTMConnection.LCIMProtocol.protobuf3]
        {
            let connectionMap: () -> [String : [String : RTMConnection]] = {
                RTMConnectionManager.default.getMap(protocol: imProtocol)
            }
            let peerID1 = "peerID1"
            let peerID2 = "peerID2"
            do {
                _ = try RTMConnectionManager.default.register(
                    application: application,
                    service: .instantMessaging(ID: peerID1, protocol: imProtocol)
                )
                XCTAssertNotNil(connectionMap()[application.id]?[peerID1])
                XCTAssertEqual(connectionMap()[application.id]?.count, 1)
            } catch {
                XCTFail("\(error)")
            }
            do {
                _ = try RTMConnectionManager.default.register(
                    application: application,
                    service: .instantMessaging(ID: peerID1, protocol: imProtocol)
                )
                XCTFail()
            } catch {
                XCTAssertTrue(error is LCError)
            }
            
            _ = try! RTMConnectionManager.default.register(
                application: application,
                service: .instantMessaging(ID: peerID2, protocol: imProtocol)
            )
            XCTAssertTrue(connectionMap()[application.id]?[peerID1] === connectionMap()[application.id]?[peerID2])
            XCTAssertEqual(connectionMap()[application.id]?.count, 2)
            
            RTMConnectionManager.default.unregister(
                application: application,
                service: .instantMessaging(ID: peerID1, protocol: imProtocol)
            )
            RTMConnectionManager.default.unregister(
                application: application,
                service: .instantMessaging(ID: peerID2, protocol: imProtocol)
            )
            
            XCTAssertEqual(connectionMap()[application.id]?.count, 0)
            
            _ = try! RTMConnectionManager.default.register(
                application: application,
                service: .instantMessaging(ID: peerID1, protocol: imProtocol)
            )
            XCTAssertNotNil(connectionMap()[application.id]?[peerID1])
            XCTAssertEqual(connectionMap()[application.id]?.count, 1)
        }
        XCTAssertEqual(RTMConnectionManager.default.protobuf1Map[application.id]?.count, 1)
        XCTAssertEqual(RTMConnectionManager.default.protobuf3Map[application.id]?.count, 1)
    }
    
    func testDeinit() {
        let peerID = uuid
        var tuple: (RTMConnection, Delegator)? = connectedConnection(peerID: peerID)
        var connection: RTMConnection? = tuple?.0
        
        let deinitExp = expectation(description: "deinit")
        let commandCallback = RTMConnection.CommandCallback(timeoutInterval: 30, callingQueue: .main, closure: { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result.error?.code, LCError.InternalErrorCode.connectionLost.rawValue)
            deinitExp.fulfill()
        })
        connection?.serialQueue.async {
            connection?.timer?.insert(commandCallback: commandCallback, index: 0)
            RTMConnectionManager.default.unregister(
                application: .default,
                service: .instantMessaging(ID: peerID, protocol: .protobuf1)
            )
            connection = nil
            tuple = nil
        }
        wait(for: [deinitExp], timeout: timeout)
    }
    
    func testTimerCommandTimeout() {
        let commandTimeoutInterval: TimeInterval = 5.0
        
        let peerID = uuid
        let tuple = connectedConnection(peerID: peerID)
        let connection = tuple.0
        
        let timeoutExp = expectation(description: "command callback timeout")
        let start = Date().timeIntervalSince1970
        let commandCallback = RTMConnection.CommandCallback(timeoutInterval: commandTimeoutInterval, callingQueue: .main) { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result.error?.code, LCError.InternalErrorCode.commandTimeout.rawValue)
            let interval = Date().timeIntervalSince1970 - start
            XCTAssertTrue(((commandTimeoutInterval - 3)...(commandTimeoutInterval + 3)) ~= interval)
            timeoutExp.fulfill()
        }
        connection.serialQueue.async {
            connection.timer?.insert(commandCallback: commandCallback, index: connection.underlyingSerialIndex)
        }
        wait(for: [timeoutExp], timeout: commandTimeoutInterval * 2)
        
        delay()
        
        XCTAssertEqual(connection.timer?.commandCallbackCollection.count, 0)
        XCTAssertEqual(connection.timer?.commandIndexSequence.count, 0)
    }
    
    func testDelegateEvent() {
        let peerID = uuid
        let tuple = connectedConnection(peerID: peerID)
        let connection = tuple.0
        let delegator = tuple.1
        
        let disconnectExp = expectation(description: "disconnect")
        delegator.didDisconnect = { con, err in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(connection === con)
            XCTAssertEqual(err.code, LCError.InternalErrorCode.connectionLost.rawValue)
            disconnectExp.fulfill()
        }
        connection.disconnect()
        wait(for: [disconnectExp], timeout: timeout)
        
        let reconnectExp = expectation(description: "reconnect")
        reconnectExp.expectedFulfillmentCount = 2
        delegator.inConnecting = { con in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(connection === con)
            reconnectExp.fulfill()
        }
        delegator.didConnect = { con in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(connection === con)
            reconnectExp.fulfill()
        }
        connection.connect()
        wait(for: [reconnectExp], timeout: timeout)
    }
    
    func testConnectionShared() {
        let tuple = connectedConnection()
        let connection = tuple.0
        
        let peerID = uuid
        let delegator = Delegator()
        let connectionDelegator = RTMConnection.Delegator(queue: .main)
        connectionDelegator.delegate = delegator
        
        let exp = expectation(description: "connected")
        let unexp1 = expectation(description: "unexpect")
        unexp1.isInverted = true
        delegator.inConnecting = { con in
            unexp1.fulfill()
        }
        delegator.didConnect = { con in
            exp.fulfill()
        }
        connection.connect(
            service: .instantMessaging(ID: peerID, protocol: .protobuf3),
            delegator: connectionDelegator
        )
        wait(for: [exp, unexp1], timeout: 5)
        
        XCTAssertEqual(connection.allDelegators.count, 2)
        connection.removeDelegator(service: .instantMessaging(ID: peerID, protocol: .protobuf3))
        
        let unexp2 = expectation(description: "unexpect")
        unexp2.isInverted = true
        delegator.didDisconnect = { _, _ in
            unexp2.fulfill()
        }
        wait(for: [unexp2], timeout: 5)
        
        XCTAssertEqual(connection.allDelegators.count, 1)
    }
    
    func testCommandSending() {
        let peerID = uuid
        let tuple = connectedConnection(peerID: peerID)
        let connection = tuple.0
        let delegator = tuple.1
        
        XCTAssertEqual(connection.underlyingSerialIndex, 1)
        
        let sendExp1 = expectation(description: "send command")
        connection.send(command: testableCommand(peerID: peerID), callingQueue: .main) { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNotNil(result.command)
            XCTAssertNil(result.error)
            sendExp1.fulfill()
        }
        wait(for: [sendExp1], timeout: timeout)
        
        XCTAssertEqual(connection.underlyingSerialIndex, 2)
        
        let sendExp2 = expectation(description: "send command with big size")
        var largeCommand = testableCommand(peerID: peerID)
        largeCommand.peerID = String(repeating: "a", count: 5000)
        connection.send(command: largeCommand, callingQueue: .main) { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result.error?.code, LCError.InternalErrorCode.commandDataLengthTooLong.rawValue)
            sendExp2.fulfill()
        }
        wait(for: [sendExp2], timeout: timeout)
        
        XCTAssertEqual(connection.underlyingSerialIndex, 3)
        
        let disconnectExp = expectation(description: "disconnect")
        delegator.didDisconnect = { _, _ in
            disconnectExp.fulfill()
        }
        connection.disconnect()
        wait(for: [disconnectExp], timeout: timeout)
        
        let sendExp3 = expectation(description: "send command when connection lost")
        connection.send(command: testableCommand(peerID: peerID), callingQueue: .main) { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(result.command)
            XCTAssertEqual(result.error?.code, LCError.InternalErrorCode.connectionLost.rawValue)
            sendExp3.fulfill()
        }
        wait(for: [sendExp3], timeout: timeout)
        
        XCTAssertEqual(connection.underlyingSerialIndex, 3)
    }
    
    func testGoaway() {
        let tuple = connectedConnection()
        let connection = tuple.0
        let delegator = tuple.1
        
        let oldDate = Date().timeIntervalSince1970
        
        expecting(expectation: {
            let exp = self.expectation(description: "goaway")
            exp.expectedFulfillmentCount = 3
            return exp
        }) { exp in
            NotificationCenter.default.addObserver(
                forName: RTMConnection.TestGoawayCommandReceivedNotification,
                object: connection,
                queue: OperationQueue.main)
            { _ in
                exp.fulfill()
            }
            delegator.didDisconnect = { _, error in
                XCTAssertEqual(error.code, LCError.InternalErrorCode.connectionLost.rawValue)
                exp.fulfill()
            }
            delegator.didConnect = { _ in
                exp.fulfill()
            }
            connection.serialQueue.async {
                connection.websocketDidReceiveData(socket: connection.socket!, data: {
                    var goaway = IMGenericCommand()
                    goaway.cmd = .goaway
                    return try! goaway.serializedData()
                }())
            }
        }
        
        XCTAssertNotNil(connection.rtmRouter?.table)
        XCTAssertGreaterThan(connection.rtmRouter!.table!.createdTimestamp, oldDate)
    }

}

extension RTMConnectionTestCase {
    
    func connectedConnection(
        application: LCApplication = .default,
        peerID: String = uuid)
        -> (RTMConnection, Delegator)
    {
        let connection = try! RTMConnectionManager.default.register(
            application: application,
            service: .instantMessaging(ID: peerID, protocol: .protobuf1)
        )
        let delegator = Delegator()
        let connectionDelegator = RTMConnection.Delegator(queue: .main)
        connectionDelegator.delegate = delegator
        let connectExp = expectation(description: "connect")
        delegator.didConnect = { con in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(connection === con)
            connectExp.fulfill()
        }
        connection.connect(
            service: .instantMessaging(ID: peerID, protocol: .protobuf3),
            delegator: connectionDelegator
        )
        wait(for: [connectExp], timeout: timeout)
        return (connection, delegator)
    }
    
    func testableCommand(application: LCApplication = .default, peerID: String = uuid) -> IMGenericCommand {
        var outCommand = IMGenericCommand()
        outCommand.cmd = .session
        outCommand.op = .open
        outCommand.appID = application.id
        outCommand.peerID = peerID
        var sessionCommand = IMSessionCommand()
        sessionCommand.ua = application.httpClient.configuration.userAgent
        outCommand.sessionMessage = sessionCommand
        return outCommand
    }
    
    class Delegator: RTMConnectionDelegate {
        
        var inConnecting: ((RTMConnection) -> Void)?
        func connection(inConnecting connection: RTMConnection) {
            inConnecting?(connection)
        }
        
        var didConnect: ((RTMConnection) -> Void)?
        func connection(didConnect connection: RTMConnection) {
            didConnect?(connection)
        }
        
        var didDisconnect: ((RTMConnection, LCError) -> Void)?
        func connection(_ connection: RTMConnection, didDisconnect error: LCError) {
            didDisconnect?(connection, error)
        }
        
        var didReceiveCommand: ((RTMConnection, IMGenericCommand) -> Void)?
        func connection(_ connection: RTMConnection, didReceiveCommand inCommand: IMGenericCommand) {
            didReceiveCommand?(connection, inCommand)
        }
        
    }
    
}
