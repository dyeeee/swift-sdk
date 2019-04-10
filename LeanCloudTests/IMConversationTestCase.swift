//
//  IMConversationTestCase.swift
//  LeanCloudTests
//
//  Created by zapcannon87 on 2019/1/20.
//  Copyright © 2019 LeanCloud. All rights reserved.
//

import XCTest
import Alamofire
@testable import LeanCloud

class IMConversationTestCase: RTMBaseTestCase {
    
    static let v2Router = HTTPRouter(
        application: .default,
        configuration: HTTPRouter.Configuration(apiVersion: "1.2")
    )

    func testCreateConversationThenErrorThrows() {
        
        let client: IMClient = try! IMClient(ID: uuid)
        
        let errExp = expectation(description: "not open")
        try? client.createConversation(clientIDs: [], isUnique: false) { (r) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertFalse(r.isSuccess)
            XCTAssertNotNil(r.error)
            errExp.fulfill()
        }
        wait(for: [errExp], timeout: timeout)
        
        do {
            let invalidID: String = Array<String>.init(repeating: "a", count: 65).joined()
            try client.createConversation(clientIDs: [invalidID], isUnique: false, completion: { (_) in })
            XCTFail()
        } catch {
            XCTAssertTrue(error is LCError)
        }
    }
    
    func testCreateNormalConversation() {
        guard
            let clientA = newOpenedClient(),
            let clientB = newOpenedClient()
            else
        {
            XCTFail()
            return
        }
        
        let delegatorA = IMClientTestCase.Delegator()
        clientA.delegate = delegatorA
        let delegatorB = IMClientTestCase.Delegator()
        clientB.delegate = delegatorB
        
        let name: String? = "normalConv"
        let attribution: [String: Any]? = [
            "String": "",
            "Int": 1,
            "Double": 1.0,
            "Bool": true,
            "Array": Array<String>(),
            "Dictionary": Dictionary<String, Any>()
        ]
        
        let convAssertion: (IMConversation, IMClient) -> Void = { conv, client in
            XCTAssertTrue(type(of: conv) == IMConversation.self)
            XCTAssertEqual(conv.lcType, .normal)
            XCTAssertEqual(conv.members?.count, 2)
            XCTAssertEqual(conv.members?.contains(clientA.ID), true)
            XCTAssertEqual(conv.members?.contains(clientB.ID), true)
            XCTAssertNotNil(conv.client)
            if let c: IMClient = conv.client {
                XCTAssertTrue(c === client)
            }
            XCTAssertEqual(conv.clientID, client.ID)
            XCTAssertFalse(conv.isUnique)
            XCTAssertNil(conv.uniqueID)
            XCTAssertEqual(conv.creator, clientA.ID)
            XCTAssertNotNil(conv.createdAt)
            XCTAssertFalse(conv.isMuted)
            XCTAssertFalse(conv.isOutdated)
            XCTAssertNil(conv.lastMessage)
            XCTAssertEqual(conv.unreadMessageCount, 0)
            XCTAssertFalse(conv.isUnreadMessageContainMention)
            if let name: String = name {
                XCTAssertEqual(name, conv.name)
            } else {
                XCTAssertNil(conv.name)
            }
            if let attribution: [String: Any] = attribution {
                XCTAssertEqual(attribution.count, conv.attributes?.count)
                for (key, value) in attribution {
                    switch key {
                    case "String":
                        XCTAssertEqual(value as? String, conv.attributes?[key] as? String)
                    case "Int":
                        XCTAssertEqual(value as? Int, conv.attributes?[key] as? Int)
                    case "Double":
                        XCTAssertEqual(value as? Double, conv.attributes?[key] as? Double)
                    case "Bool":
                        XCTAssertEqual(value as? Bool, conv.attributes?[key] as? Bool)
                    case "Array":
                        XCTAssertEqual((value as? Array<String>)?.isEmpty, true)
                        XCTAssertEqual((conv.attributes?[key] as? Array<String>)?.isEmpty, true)
                    case "Dictionary":
                        XCTAssertEqual((value as? Dictionary<String, Any>)?.isEmpty, true)
                        XCTAssertEqual((conv.attributes?[key] as? Dictionary<String, Any>)?.isEmpty, true)
                    default:
                        XCTFail()
                    }
                }
            } else {
                XCTAssertNil(attribution)
            }
        }
        
        let exp = expectation(description: "create conversation")
        exp.expectedFulfillmentCount = 5
        delegatorA.conversationEvent = { client, conv, event in
            XCTAssertTrue(Thread.isMainThread)
            if client === clientA {
                convAssertion(conv, client)
                XCTAssertNil(conv.updatedAt)
                switch event {
                case .joined(byClientID: let cID):
                    XCTAssertEqual(cID, clientA.ID)
                    exp.fulfill()
                case .membersJoined(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(Set(members), Set([clientA.ID, clientB.ID]))
                    exp.fulfill()
                default:
                    break
                }
            }
        }
        delegatorB.conversationEvent = { client, conv, event in
            XCTAssertTrue(Thread.isMainThread)
            if client === clientB {
                convAssertion(conv, client)
                XCTAssertNotNil(conv.updatedAt)
                switch event {
                case .joined(byClientID: let cID):
                    XCTAssertEqual(cID, clientA.ID)
                    exp.fulfill()
                case .membersJoined(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(Set(members), Set([clientA.ID, clientB.ID]))
                    exp.fulfill()
                default:
                    break
                }
            }
        }
        try? clientA.createConversation(clientIDs: [clientA.ID, clientB.ID], name: name, attributes: attribution, isUnique: false) { (result) in
            XCTAssertTrue(Thread.isMainThread)
            if let conv: IMConversation = result.value {
                convAssertion(conv, clientA)
                XCTAssertNil(conv.updatedAt)
            } else {
                XCTFail()
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        
        XCTAssertEqual(clientA.convCollection.count, 1)
        XCTAssertEqual(clientB.convCollection.count, 1)
        XCTAssertEqual(
            clientA.convCollection.first?.value.ID,
            clientB.convCollection.first?.value.ID
        )
        XCTAssertTrue(clientA.convQueryCallbackCollection.isEmpty)
        XCTAssertTrue(clientB.convQueryCallbackCollection.isEmpty)
    }
    
    func testCreateNormalAndUniqueConversation() {
        guard
            let clientA = newOpenedClient(customRTMURL: testableRTMURL),
            let clientB = newOpenedClient(customRTMURL: testableRTMURL)
            else
        {
            XCTFail()
            return
        }
        
        let exp1 = expectation(description: "create unique conversation")
        try? clientA.createConversation(clientIDs: [clientA.ID, clientB.ID], completion: { (result) in
            if let conv: IMConversation = result.value {
                XCTAssertTrue(type(of: conv) == IMConversation.self)
                XCTAssertEqual(conv.lcType, .normal)
                XCTAssertTrue(conv.isUnique)
                XCTAssertNotNil(conv.uniqueID)
            } else {
                XCTFail()
            }
            exp1.fulfill()
        })
        wait(for: [exp1], timeout: timeout)
        
        let exp2 = expectation(description: "create unique conversation")
        try? clientB.createConversation(clientIDs: [clientA.ID, clientB.ID], completion: { (result) in
            if let conv: IMConversation = result.value {
                XCTAssertTrue(type(of: conv) == IMConversation.self)
                XCTAssertEqual(conv.lcType, .normal)
                XCTAssertTrue(conv.isUnique)
                XCTAssertNotNil(conv.uniqueID)
            } else {
                XCTFail()
            }
            exp2.fulfill()
        })
        wait(for: [exp2], timeout: timeout)
        
        XCTAssertEqual(
            clientA.convCollection.first?.value.ID,
            clientB.convCollection.first?.value.ID
        )
        XCTAssertEqual(
            clientA.convCollection.first?.value.uniqueID,
            clientB.convCollection.first?.value.uniqueID
        )
    }
    
    func testCreateChatRoom() {
        guard let client = newOpenedClient() else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "create chat room")
        try? client.createChatRoom() { (result) in
            XCTAssertTrue(Thread.isMainThread)
            let chatRoom: IMChatRoom? = result.value
            XCTAssertEqual(chatRoom?.lcType, .transient)
            if let members = chatRoom?.members {
                XCTAssertTrue(members.isEmpty)
            } else {
                XCTAssertNil(chatRoom?.members)
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: timeout, handler: nil)
    }
    
    func testCreateTemporaryConversation() {
        guard
            let clientA = newOpenedClient(),
            let clientB = newOpenedClient()
            else
        {
            XCTFail()
            return
        }
        let delegatorA = IMClientTestCase.Delegator()
        clientA.delegate = delegatorA
        let delegatorB = IMClientTestCase.Delegator()
        clientB.delegate = delegatorB
        
        let ttl: Int32 = 3600
        
        let exp = expectation(description: "create conversation")
        exp.expectedFulfillmentCount = 5
        delegatorA.conversationEvent = { client, conv, event in
            XCTAssertTrue(Thread.isMainThread)
            if client === clientA {
                XCTAssertEqual(conv.lcType, .temporary)
                XCTAssertEqual((conv as? IMTemporaryConversation)?.timeToLive, Int(ttl))
                switch event {
                case .joined(byClientID: let cID):
                    XCTAssertEqual(cID, clientA.ID)
                    exp.fulfill()
                case .membersJoined(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(Set(members), Set([clientA.ID, clientB.ID]))
                    exp.fulfill()
                default:
                    break
                }
            }
        }
        delegatorB.conversationEvent = { client, conv, event in
            XCTAssertTrue(Thread.isMainThread)
            if client === clientB {
                XCTAssertEqual(conv.lcType, .temporary)
                XCTAssertEqual((conv as? IMTemporaryConversation)?.timeToLive, Int(ttl))
                switch event {
                case .joined(byClientID: let cID):
                    XCTAssertEqual(cID, clientA.ID)
                    exp.fulfill()
                case .membersJoined(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(Set(members), Set([clientA.ID, clientB.ID]))
                    exp.fulfill()
                default:
                    break
                }
            }
        }
        try? clientA.createTemporaryConversation(clientIDs: [clientA.ID, clientB.ID], timeToLive: ttl, completion: { (result) in
            XCTAssertTrue(Thread.isMainThread)
            if let conv: IMTemporaryConversation = result.value {
                XCTAssertEqual(conv.lcType, .temporary)
                XCTAssertEqual(conv.timeToLive, Int(ttl))
            } else {
                XCTFail()
            }
            exp.fulfill()
        })
        waitForExpectations(timeout: timeout, handler: nil)
        
        XCTAssertEqual(
            clientA.convCollection.first?.value.ID,
            clientB.convCollection.first?.value.ID
        )
        XCTAssertEqual(
            clientA.convCollection.first?.value.ID.hasPrefix(IMTemporaryConversation.prefixOfID),
            true
        )
    }
    
    func testNormalConversationUnreadEvent() {
        guard let clientA = newOpenedClient() else {
            XCTFail()
            return
        }
        
        let otherClientID: String = uuid
        let message = IMMessage()
        try? message.set(content: .string("test"))
        message.isAllMembersMentioned = true
        
        let sendExp = expectation(description: "create conversation and send message")
        sendExp.expectedFulfillmentCount = 2
        try? clientA.createConversation(clientIDs: [otherClientID], isUnique: false, completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            try? result.value?.send(message: message, completion: { (result) in
                XCTAssertTrue(result.isSuccess)
                sendExp.fulfill()
            })
            sendExp.fulfill()
        })
        wait(for: [sendExp], timeout: timeout)
        
        let clientB = try! IMClient(ID: otherClientID)
        let delegatorB = IMClientTestCase.Delegator()
        clientB.delegate = delegatorB
        
        let unreadExp = expectation(description: "opened and get unread event")
        unreadExp.expectedFulfillmentCount = 3
        delegatorB.conversationEvent = { client, conversation, event in
            if client === clientB, conversation.ID == message.conversationID {
                switch event {
                case .lastMessageUpdated:
                    XCTAssertEqual(conversation.lastMessage?.conversationID, message.conversationID)
                    XCTAssertEqual(conversation.lastMessage?.sentTimestamp, message.sentTimestamp)
                    XCTAssertEqual(conversation.lastMessage?.ID, message.ID)
                    unreadExp.fulfill()
                case .unreadMessageCountUpdated:
                    XCTAssertEqual(conversation.unreadMessageCount, 1)
                    XCTAssertTrue(conversation.isUnreadMessageContainMention)
                    unreadExp.fulfill()
                default:
                    break
                }
            }
        }
        clientB.open { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            unreadExp.fulfill()
        }
        wait(for: [unreadExp], timeout: timeout)
        
        delay()
        XCTAssertNotNil(clientB.lastUnreadNotifTime)
        
        let reconnectExp = expectation(description: "reconnect")
        let notGetUnreadExp = expectation(description: "not get unread event")
        notGetUnreadExp.isInverted = true
        delegatorB.clientEvent = { client, event in
            switch event {
            case .sessionDidOpen:
                reconnectExp.fulfill()
            default:
                break
            }
        }
        delegatorB.conversationEvent = { client, conversation, event in
            if conversation.ID == message.conversationID {
                if case .unreadMessageCountUpdated = event {
                    notGetUnreadExp.fulfill()
                }
            }
        }
        clientB.connection.disconnect()
        clientB.connection.connect()
        wait(for: [reconnectExp, notGetUnreadExp], timeout: 5)
        
        let readExp = expectation(description: "read")
        delegatorB.conversationEvent = { client, conversation, event in
            if conversation.ID == message.conversationID {
                if case .unreadMessageCountUpdated = event {
                    XCTAssertEqual(conversation.unreadMessageCount, 0)
                    readExp.fulfill()
                }
            }
        }
        for (_, conv) in clientB.convCollection {
            conv.read()
        }
        wait(for: [readExp], timeout: timeout)
    }
    
    func testTemporaryConversationUnreadEvent() {
        guard let clientA = newOpenedClient() else {
            XCTFail()
            return
        }
        
        let otherClientID: String = uuid
        let message = IMMessage()
        try? message.set(content: .string("test"))
        message.isAllMembersMentioned = true
        
        let sendExp = expectation(description: "create temporary conversation and send message")
        sendExp.expectedFulfillmentCount = 2
        try? clientA.createTemporaryConversation(clientIDs: [otherClientID], timeToLive: 3600, completion: { (result) in
            XCTAssertNotNil(result.value)
            try? result.value?.send(message: message, completion: { (result) in
                XCTAssertTrue(result.isSuccess)
                sendExp.fulfill()
            })
            sendExp.fulfill()
        })
        wait(for: [sendExp], timeout: timeout)
        
        let clientB = try! IMClient(ID: otherClientID)
        let delegator = IMClientTestCase.Delegator()
        clientB.delegate = delegator
        
        let unreadExp = expectation(description: "opened and get unread event")
        unreadExp.expectedFulfillmentCount = 3
        delegator.conversationEvent = { client, conversation, event in
            if client === clientB, conversation.ID == message.conversationID {
                switch event {
                case .lastMessageUpdated:
                    XCTAssertEqual(conversation.lastMessage?.conversationID, message.conversationID)
                    XCTAssertEqual(conversation.lastMessage?.sentTimestamp, message.sentTimestamp)
                    XCTAssertEqual(conversation.lastMessage?.ID, message.ID)
                    unreadExp.fulfill()
                case .unreadMessageCountUpdated:
                    XCTAssertEqual(conversation.unreadMessageCount, 1)
                    XCTAssertTrue(conversation.isUnreadMessageContainMention)
                    unreadExp.fulfill()
                default:
                    break
                }
            }
        }
        clientB.open { (result) in
            XCTAssertTrue(result.isSuccess)
            unreadExp.fulfill()
        }
        wait(for: [unreadExp], timeout: timeout)
        
        let readExp = expectation(description: "read")
        delegator.conversationEvent = { client, conversation, event in
            if client === clientB, conversation.ID == message.conversationID {
                if case .unreadMessageCountUpdated = event {
                    XCTAssertEqual(conversation.unreadMessageCount, 0)
                    readExp.fulfill()
                }
            }
        }
        for (_, conv) in clientB.convCollection {
            conv.read()
        }
        wait(for: [readExp], timeout: timeout)
    }
    
    func testServiceConversationUnreadEvent() {
        
        let clientID = uuid
        
        guard let serviceConvID: String = IMConversationTestCase.newServiceConversation(),
            IMConversationTestCase.subscribing(serviceConversation: serviceConvID, by: clientID),
            let _ = IMConversationTestCase.broadcastingMessage(to: serviceConvID)
            else
        {
            XCTFail()
            return
        }
        
        delay(seconds: 15)
        
        let clientA = try! IMClient(ID: clientID)
        let delegator = IMClientTestCase.Delegator()
        clientA.delegate = delegator
        
        let unreadExp = expectation(description: "opened and get unread event")
        unreadExp.expectedFulfillmentCount = 3
        delegator.conversationEvent = { client, conversation, event in
            if client === clientA, conversation.ID == serviceConvID {
                switch event {
                case .lastMessageUpdated:
                    unreadExp.fulfill()
                case .unreadMessageCountUpdated:
                    unreadExp.fulfill()
                default:
                    break
                }
            }
        }
        clientA.open { (result) in
            XCTAssertTrue(result.isSuccess)
            unreadExp.fulfill()
        }
        wait(for: [unreadExp], timeout: timeout)
        
        let readExp = expectation(description: "read")
        delegator.conversationEvent = { client, conversation, event in
            if client === clientA, conversation.ID == serviceConvID {
                if case .unreadMessageCountUpdated = event {
                    XCTAssertEqual(conversation.unreadMessageCount, 0)
                    readExp.fulfill()
                }
            }
        }
        for (_, conv) in clientA.convCollection {
            conv.read()
        }
        wait(for: [readExp], timeout: timeout)
    }
    
    func testLargeUnreadEvent() {
        guard let clientA = newOpenedClient() else {
            XCTFail()
            return
        }
        
        let otherClientID: String = uuid
        let count: Int = 20
        
        for i in 0..<count {
            let exp = expectation(description: "create conversation and send message")
            exp.expectedFulfillmentCount = 2
            let message = IMMessage()
            try? message.set(content: .string("test"))
            if i % 2 == 0 {
                try! clientA.createTemporaryConversation(clientIDs: [otherClientID, uuid], timeToLive: 3600, completion: { (result) in
                    XCTAssertNotNil(result.value)
                    try! result.value?.send(message: message, completion: { (result) in
                        XCTAssertTrue(result.isSuccess)
                        exp.fulfill()
                    })
                    exp.fulfill()
                })
                wait(for: [exp], timeout: timeout)
            } else {
                try! clientA.createConversation(clientIDs: [otherClientID], isUnique: false) { (result) in
                    XCTAssertNotNil(result.value)
                    try! result.value?.send(message: message, completion: { (result) in
                        XCTAssertTrue(result.isSuccess)
                        exp.fulfill()
                    })
                    exp.fulfill()
                }
                wait(for: [exp], timeout: timeout)
            }
        }
        
        let convIDSet = Set<String>(clientA.convCollection.keys)
        let clientB = try! IMClient(ID: otherClientID)
        let delegator = IMClientTestCase.Delegator()
        clientB.delegate = delegator
        
        let largeUnreadExp = expectation(description: "opened and get large unread event")
        largeUnreadExp.expectedFulfillmentCount = (count * 2) + 1
        delegator.conversationEvent = { client, conversaton, event in
            if client === clientB, convIDSet.contains(conversaton.ID) {
                switch event {
                case .lastMessageUpdated, .unreadMessageCountUpdated:
                    largeUnreadExp.fulfill()
                default:
                    break
                }
            }
        }
        clientB.open { (result) in
            XCTAssertTrue(result.isSuccess)
            largeUnreadExp.fulfill()
        }
        wait(for: [largeUnreadExp], timeout: timeout)
        
        XCTAssertNotNil(clientB.lastUnreadNotifTime)
        
        let allReadExp = expectation(description: "all read")
        allReadExp.expectedFulfillmentCount = count
        delegator.conversationEvent = { client, conversation, event in
            if client === clientB, convIDSet.contains(conversation.ID) {
                if case .unreadMessageCountUpdated = event {
                    allReadExp.fulfill()
                }
            }
        }
        for (_, conv) in clientB.convCollection {
            conv.read()
        }
        wait(for: [allReadExp], timeout: timeout)
    }
    
    func testMembersChange() {
        guard
            let clientA = newOpenedClient(),
            let clientB = newOpenedClient()
            else
        {
            XCTFail()
            return
        }
        
        let delegatorA = IMClientTestCase.Delegator()
        clientA.delegate = delegatorA
        let delegatorB = IMClientTestCase.Delegator()
        clientB.delegate = delegatorB
        var convA: IMConversation? = nil
        
        let createConvExp = expectation(description: "create conversation")
        createConvExp.expectedFulfillmentCount = 5
        delegatorA.conversationEvent = { client, conv, event in
            switch event {
            case .joined(byClientID: let byClientID):
                XCTAssertEqual(byClientID, clientA.ID)
                createConvExp.fulfill()
            case .membersJoined(members: let members, byClientID: let byClientID):
                XCTAssertEqual(byClientID, clientA.ID)
                XCTAssertEqual(Set(members), Set([clientA.ID, clientB.ID]))
                createConvExp.fulfill()
            default:
                break
            }
        }
        delegatorB.conversationEvent = { client, conv, event in
            switch event {
            case .joined(byClientID: let byClientID):
                XCTAssertEqual(byClientID, clientA.ID)
                createConvExp.fulfill()
            case .membersJoined(members: let members, byClientID: let byClientID):
                XCTAssertEqual(byClientID, clientA.ID)
                XCTAssertEqual(Set(members), Set([clientA.ID, clientB.ID]))
                createConvExp.fulfill()
            default:
                break
            }
        }
        try? clientA.createConversation(clientIDs: [clientA.ID, clientB.ID], isUnique: false) { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            convA = result.value
            createConvExp.fulfill()
        }
        wait(for: [createConvExp], timeout: timeout)
        
        let convB = clientB.convCollection[convA?.ID ?? ""]
        
        let leaveAndJoinExp = expectation(description: "leave and join")
        leaveAndJoinExp.expectedFulfillmentCount = 6
        delegatorA.conversationEvent = { client, conv, event in
            if conv === convA {
                switch event {
                case .membersJoined(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientB.ID)
                    XCTAssertEqual(members.count, 1)
                    XCTAssertEqual(members.first, clientB.ID)
                    XCTAssertEqual(conv.members?.count, 2)
                    XCTAssertEqual(conv.members?.contains(clientA.ID), true)
                    XCTAssertEqual(conv.members?.contains(clientB.ID), true)
                    leaveAndJoinExp.fulfill()
                case .membersLeft(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientB.ID)
                    XCTAssertEqual(members.count, 1)
                    XCTAssertEqual(members.first, clientB.ID)
                    XCTAssertEqual(conv.members?.count, 1)
                    XCTAssertEqual(conv.members?.first, clientA.ID)
                    leaveAndJoinExp.fulfill()
                default:
                    break
                }
            }
        }
        delegatorB.conversationEvent = { client, conv, event in
            if conv === convB {
                switch event {
                case .joined(byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientB.ID)
                    XCTAssertEqual(conv.members?.count, 2)
                    XCTAssertEqual(conv.members?.contains(clientA.ID), true)
                    XCTAssertEqual(conv.members?.contains(clientB.ID), true)
                    leaveAndJoinExp.fulfill()
                case .left(byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientB.ID)
                    XCTAssertEqual(conv.members?.count, 1)
                    XCTAssertEqual(conv.members?.first, clientA.ID)
                    leaveAndJoinExp.fulfill()
                default:
                    break
                }
            }
        }
        ((try? convB?.leave(completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(convB?.members?.count, 1)
            XCTAssertEqual(convB?.members?.first, clientA.ID)
            leaveAndJoinExp.fulfill()
            try? convB?.join(completion: { (result) in
                XCTAssertTrue(result.isSuccess)
                XCTAssertNil(result.error)
                XCTAssertEqual(convB?.members?.count, 2)
                XCTAssertEqual(convB?.members?.contains(clientA.ID), true)
                XCTAssertEqual(convB?.members?.contains(clientB.ID), true)
                leaveAndJoinExp.fulfill()
            })
        })) as ()??)
        wait(for: [leaveAndJoinExp], timeout: timeout)
        
        let removeAndAddExp = expectation(description: "remove and add")
        removeAndAddExp.expectedFulfillmentCount = 6
        delegatorA.conversationEvent = { client, conv, event in
            if conv === convA {
                switch event {
                case .membersJoined(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(members.count, 1)
                    XCTAssertEqual(members.first, clientB.ID)
                    XCTAssertEqual(conv.members?.count, 2)
                    XCTAssertEqual(conv.members?.contains(clientA.ID), true)
                    XCTAssertEqual(conv.members?.contains(clientB.ID), true)
                    removeAndAddExp.fulfill()
                case .membersLeft(members: let members, byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(members.count, 1)
                    XCTAssertEqual(members.first, clientB.ID)
                    XCTAssertEqual(conv.members?.count, 1)
                    XCTAssertEqual(conv.members?.first, clientA.ID)
                    removeAndAddExp.fulfill()
                default:
                    break
                }
            }
        }
        delegatorB.conversationEvent = { client, conv, event in
            if conv === convB {
                switch event {
                case .joined(byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(conv.members?.count, 2)
                    XCTAssertEqual(conv.members?.contains(clientA.ID), true)
                    XCTAssertEqual(conv.members?.contains(clientB.ID), true)
                    removeAndAddExp.fulfill()
                case .left(byClientID: let byClientID):
                    XCTAssertEqual(byClientID, clientA.ID)
                    XCTAssertEqual(conv.members?.count, 1)
                    XCTAssertEqual(conv.members?.first, clientA.ID)
                    removeAndAddExp.fulfill()
                default:
                    break
                }
            }
        }
        ((try? convA?.remove(members: [clientB.ID], completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(convA?.members?.count, 1)
            XCTAssertEqual(convA?.members?.first, clientA.ID)
            removeAndAddExp.fulfill()
            try? convA?.add(members: [clientB.ID], completion: { (result) in
                XCTAssertTrue(result.isSuccess)
                XCTAssertNil(result.error)
                XCTAssertEqual(convA?.members?.count, 2)
                XCTAssertEqual(convA?.members?.contains(clientA.ID), true)
                XCTAssertEqual(convA?.members?.contains(clientB.ID), true)
                removeAndAddExp.fulfill()
            })
        })) as ()??)
        wait(for: [removeAndAddExp], timeout: timeout)
    }
    
    func testGetChatRoomOnlineCount() {
        guard
            let clientA = newOpenedClient(),
            let clientB = newOpenedClient()
            else
        {
            XCTFail()
            return
        }
        
        var chatRoomA: IMChatRoom? = nil
        
        let createExp = expectation(description: "create chat room")
        try? clientA.createChatRoom(completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            chatRoomA = result.value
            createExp.fulfill()
        })
        wait(for: [createExp], timeout: timeout)
        
        var chatRoomB: IMChatRoom? = nil
        
        let queryExp = expectation(description: "query chat room")
        if let ID = chatRoomA?.ID {
            try? clientB.conversationQuery.getConversation(by: ID, completion: { (result) in
                XCTAssertTrue(result.isSuccess)
                XCTAssertNil(result.error)
                chatRoomB = result.value as? IMChatRoom
                queryExp.fulfill()
            })
        }
        wait(for: [queryExp], timeout: timeout)
        
        let countExp = expectation(description: "get online count")
        countExp.expectedFulfillmentCount = 5
        chatRoomA?.getOnlineMemberCount(completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.intValue, 1)
            countExp.fulfill()
            ((try? chatRoomB?.join(completion: { (result) in
                XCTAssertTrue(result.isSuccess)
                XCTAssertNil(result.error)
                countExp.fulfill()
                chatRoomA?.getOnlineMemberCount(completion: { (result) in
                    XCTAssertTrue(result.isSuccess)
                    XCTAssertNil(result.error)
                    XCTAssertEqual(result.intValue, 2)
                    countExp.fulfill()
                    try? chatRoomB?.leave(completion: { (result) in
                        XCTAssertTrue(result.isSuccess)
                        XCTAssertNil(result.error)
                        countExp.fulfill()
                        chatRoomA?.getOnlineMemberCount(completion: { (result) in
                            XCTAssertTrue(result.isSuccess)
                            XCTAssertNil(result.error)
                            XCTAssertEqual(result.intValue, 1)
                            countExp.fulfill()
                        })
                    })
                })
            })) as ()??)
        })
        wait(for: [countExp], timeout: timeout)
    }
    
    func testMuteAndUnmute() {
        guard let client = newOpenedClient() else {
            XCTFail()
            return
        }
        
        var conversation: IMConversation? = nil
        
        let createExp = expectation(description: "create conversation")
        try? client.createConversation(clientIDs: [uuid, uuid], isUnique: false) { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            conversation = result.value
            createExp.fulfill()
        }
        wait(for: [createExp], timeout: timeout)
        
        let muteExp = expectation(description: "mute")
        conversation?.mute(completion: { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(conversation?.isMuted, true)
            let mutedMembers = conversation?[IMConversation.Key.mutedMembers.rawValue] as? [String]
            XCTAssertEqual(mutedMembers?.count, 1)
            XCTAssertEqual(mutedMembers?.contains(client.ID), true)
            muteExp.fulfill()
        })
        wait(for: [muteExp], timeout: timeout)
        
        let unmuteExp = expectation(description: "unmute")
        conversation?.unmute(completion: { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(conversation?.isMuted, false)
            let mutedMembers = conversation?[IMConversation.Key.mutedMembers.rawValue] as? [String]
            XCTAssertEqual(mutedMembers?.count, 0)
            unmuteExp.fulfill()
        })
        wait(for: [unmuteExp], timeout: timeout)
    }
    
    func testConversationQuery() {
        guard let clientA = newOpenedClient() else {
            XCTFail()
            return
        }
        
        var ID1: String? = nil
        var ID2: String? = nil
        var ID3: String? = nil
        var ID4: String? = nil
        for i in 0...3 {
            switch i {
            case 0:
                let createExp = expectation(description: "create normal conversation")
                createExp.expectedFulfillmentCount = 2
                try? clientA.createConversation(clientIDs: [uuid], isUnique: false, completion: { (result) in
                    XCTAssertTrue(result.isSuccess)
                    XCTAssertNil(result.error)
                    ID1 = result.value?.ID
                    let message = IMTextMessage()
                    message.text = "test"
                    try? result.value?.send(message: message, completion: { (result) in
                        XCTAssertTrue(result.isSuccess)
                        XCTAssertNil(result.error)
                        createExp.fulfill()
                    })
                    createExp.fulfill()
                })
                wait(for: [createExp], timeout: timeout)
            case 1:
                let createExp = expectation(description: "create chat room")
                try? clientA.createChatRoom(completion: { (result) in
                    XCTAssertTrue(result.isSuccess)
                    XCTAssertNil(result.error)
                    ID2 = result.value?.ID
                    createExp.fulfill()
                })
                wait(for: [createExp], timeout: timeout)
            case 2:
                let ID = IMConversationTestCase.newServiceConversation()
                XCTAssertNotNil(ID)
                ID3 = ID
            case 3:
                let createExp = expectation(description: "create temporary conversation")
                try? clientA.createTemporaryConversation(clientIDs: [uuid], timeToLive: 3600, completion: { (result) in
                    XCTAssertTrue(result.isSuccess)
                    XCTAssertNil(result.error)
                    ID4 = result.value?.ID
                    createExp.fulfill()
                })
                wait(for: [createExp], timeout: timeout)
            default:
                break
            }
        }
        
        guard
            let normalConvID = ID1,
            let chatRoomID = ID2,
            let serviceID = ID3,
            let tempID = ID4
            else
        {
            XCTFail()
            return
        }
        
        delay()
        clientA.convCollection.removeAll()
        
        let queryExp1 = expectation(description: "query normal conversation with message and without member")
        let query1 = clientA.conversationQuery
        query1.options = [.notContainMembers, .containLastMessage]
        try? query1.getConversation(by: normalConvID) { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.value?.lcType, .normal)
            if let conv = result.value {
                XCTAssertTrue(type(of: conv) == IMConversation.self)
            }
            XCTAssertEqual(result.value?.members ?? [], [])
            XCTAssertNotNil(result.value?.lastMessage)
            queryExp1.fulfill()
        }
        wait(for: [queryExp1], timeout: timeout)
        
        let queryExp2 = expectation(description: "query chat room")
        try? clientA.conversationQuery.getConversation(by: chatRoomID, completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.value?.lcType, .transient)
            if let conv = result.value as? IMChatRoom {
                XCTAssertTrue(type(of: conv) == IMChatRoom.self)
            }
            queryExp2.fulfill()
        })
        wait(for: [queryExp2], timeout: timeout)

        let queryExp3 = expectation(description: "query service conversation")
        try? clientA.conversationQuery.getConversation(by: serviceID, completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.value?.lcType, .system)
            if let conv = result.value as? IMServiceConversation {
                XCTAssertTrue(type(of: conv) == IMServiceConversation.self)
            }
            queryExp3.fulfill()
        })
        wait(for: [queryExp3], timeout: timeout)
        
        clientA.convCollection.removeAll()
        
        let queryAllExp = expectation(description: "query all")
        queryAllExp.expectedFulfillmentCount = 4
        try? clientA.conversationQuery.getConversations(by: [normalConvID, chatRoomID, serviceID], completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.value?.count, 3)
            if let convs = result.value {
                for conv in convs {
                    switch conv.lcType {
                    case .normal:
                        queryAllExp.fulfill()
                    case .transient:
                        queryAllExp.fulfill()
                    case .system:
                        queryAllExp.fulfill()
                    default:
                        break
                    }
                }
            }
            queryAllExp.fulfill()
        })
        wait(for: [queryAllExp], timeout: timeout)
        
        let queryTempExp = expectation(description: "query temporary conversation")
        try? clientA.conversationQuery.getTemporaryConversations(by: [tempID], completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.value?.count, 1)
            queryTempExp.fulfill()
        })
        wait(for: [queryTempExp], timeout: timeout)
        
        clientA.convCollection.removeAll()
        
        let generalQueryExp1 = expectation(description: "general query with default conditon")
        try? clientA.conversationQuery.findConversations(completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.value?.count, 1)
            XCTAssertEqual(result.value?.first?.lcType, .normal)
            XCTAssertEqual(result.value?.first?.members?.contains(clientA.ID), true)
            generalQueryExp1.fulfill()
        })
        wait(for: [generalQueryExp1], timeout: timeout)
        
        let generalQueryExp2 = expectation(description: "general query with custom conditon")
        let generalQuery1 = clientA.conversationQuery
        try! generalQuery1.where(IMConversation.Key.transient.rawValue, .equalTo(true))
        let generalQuery2 = clientA.conversationQuery
        try! generalQuery2.where(IMConversation.Key.system.rawValue, .equalTo(true))
        let generalQuery3 = ((try? generalQuery1.or(generalQuery2)) as IMConversationQuery??)
        try! generalQuery3??.where(IMConversation.Key.createdAt.rawValue, .ascending)
        generalQuery3??.limit = 5
        ((try? generalQuery3??.findConversations(completion: { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            XCTAssertLessThanOrEqual(result.value?.count ?? .max, 5)
            if let convs = result.value {
                let types: [IMConversation.ConvType] = [.system, .transient]
                var date = Date(timeIntervalSince1970: 0)
                for conv in convs {
                    XCTAssertTrue(types.contains(conv.lcType))
                    XCTAssertNotNil(conv.createdAt)
                    if let createdAt = conv.createdAt {
                        XCTAssertGreaterThanOrEqual(createdAt, date)
                        date = createdAt
                    }
                }
            }
            generalQueryExp2.fulfill()
        })) as ()??)
        wait(for: [generalQueryExp2], timeout: timeout)
        
        let invalidQuery = LCQuery(className: "invalid")
        for constraint in
            [ LCQuery.Constraint.selected,
              LCQuery.Constraint.included,
              LCQuery.Constraint.matchedQuery(invalidQuery),
              LCQuery.Constraint.notMatchedQuery(invalidQuery),
              LCQuery.Constraint.matchedQueryAndKey(query: invalidQuery, key: ""),
              LCQuery.Constraint.notMatchedQueryAndKey(query: invalidQuery, key: "")]
        {
            do {
                let conversationQuery = clientA.conversationQuery
                try conversationQuery.where("key", constraint)
                XCTFail()
            } catch {
                XCTAssertTrue(error is LCError)
            }
        }
    }
    
    func testUpdating() {
        guard let clientA = newOpenedClient() else {
            XCTFail()
            return
        }
        
        RTMConnectionRefMap_protobuf1.removeAll()
        RTMConnectionRefMap_protobuf3.removeAll()
        
        guard let clientB = newOpenedClient() else {
            XCTFail()
            return
        }
        
        let delegatorA = IMClientTestCase.Delegator()
        clientA.delegate = delegatorA
        let delegatorB = IMClientTestCase.Delegator()
        clientB.delegate = delegatorB
        
        var convA: IMConversation? = nil
        var convB: IMConversation? = nil
        
        let nameKey = IMConversation.Key.name.rawValue
        let attrKey = IMConversation.Key.attributes.rawValue
        let createKey = "create"
        let deleteKey = "delete"
        let arrayKey = "array"
        
        let createConvExp = expectation(description: "create conversation")
        try? clientA.createConversation(
            clientIDs: [clientA.ID, clientB.ID],
            name: uuid,
            attributes: [
                deleteKey: uuid,
                arrayKey: [uuid]
            ],
            isUnique: false)
        { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            convA = result.value
            createConvExp.fulfill()
        }
        wait(for: [createConvExp], timeout: timeout)
        
        delay()
        
        let data: [String: Any] = [
            nameKey: uuid,
            "\(attrKey).\(createKey)": uuid,
            "\(attrKey).\(deleteKey)": ["__op": "Delete"],
            "\(attrKey).\(arrayKey)": ["__op": "Add", "objects": [uuid]]
        ]
        
        let updateExp = expectation(description: "update")
        updateExp.expectedFulfillmentCount = 2
        delegatorB.conversationEvent = { client, conv, event in
            if conv.ID == convA?.ID {
                switch event {
                case let .dataUpdated(updatedData: updatedData, byClientID: byClientID, at: at, updatingData: updatingData):
                    XCTAssertNotNil(updatedData)
                    XCTAssertNotNil(updatingData)
                    XCTAssertNotNil(at)
                    XCTAssertEqual(byClientID, clientA.ID)
                    convB = conv
                    updateExp.fulfill()
                default:
                    break
                }
            }
        }
        ((try? convA?.update(with: data, completion: { (result) in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            updateExp.fulfill()
        })) as ()??)
        wait(for: [updateExp], timeout: timeout)
        
        let check = { (conv: IMConversation?) in
            XCTAssertEqual(conv?.name, data[nameKey] as? String)
            XCTAssertEqual(conv?.attributes?[createKey] as? String, data["\(attrKey).\(createKey)"] as? String)
            XCTAssertNil(conv?.attributes?[deleteKey])
            XCTAssertNotNil(conv?.attributes?[arrayKey])
        }
        check(convA)
        check(convB)
        XCTAssertEqual(convA?.attributes?[arrayKey] as? [String], convB?.attributes?[arrayKey] as? [String])
    }
    
    func testGetOfflineEvents() {
        guard let clientB = newOpenedClient() else {
            return
        }
        
        RTMConnectionRefMap_protobuf1.removeAll()
        RTMConnectionRefMap_protobuf3.removeAll()
        
        delay()
        clientB.connection.disconnect()
        delay()
        
        guard let clientA = newOpenedClient() else {
            return
        }
        let delegatorA = IMClientTestCase.Delegator()
        clientA.delegate = delegatorA
        
        let createExp = expectation(description: "create conversation")
        createExp.expectedFulfillmentCount = 3
        delegatorA.conversationEvent = { client, conv, event in
            switch event {
            case .joined(byClientID: _):
                createExp.fulfill()
            case .membersJoined(members: _, byClientID: _):
                createExp.fulfill()
            default:
                break
            }
        }
        try? clientA.createConversation(clientIDs: [clientB.ID], isUnique: false) { (result) in
            XCTAssertTrue(result.isSuccess)
            XCTAssertNil(result.error)
            createExp.fulfill()
        }
        wait(for: [createExp], timeout: timeout)
        
        XCTAssertNotNil(clientA.localRecord.lastServerTimestamp)
        
        let saveLocalRecordExp = expectation(description: "save local record")
        let serverTimestamp = (clientA.localRecord.lastServerTimestamp ?? 0) - (60 * 1000)
        let observer = NotificationCenter.default.addObserver(forName: IMClient.TestSaveLocalRecordNotification, object: clientB, queue: .main) { (notification) in
            XCTAssertNotNil(notification.userInfo)
            XCTAssertNil(notification.userInfo?["error"])
            let table: IMClient.LocalRecord? = try! clientB.application.localStorageContext?.table(from: clientB.localRecordURL!)
            XCTAssertNotNil(table)
            XCTAssertEqual(table?.lastServerTimestamp, serverTimestamp)
            saveLocalRecordExp.fulfill()
        }
        clientB.test_change(serverTimestamp: serverTimestamp)
        wait(for: [saveLocalRecordExp], timeout: timeout)
        NotificationCenter.default.removeObserver(observer)
        
        let getEventsExp = expectation(description: "get offline events")
        getEventsExp.expectedFulfillmentCount = 3
        let delegatorB = IMClientTestCase.Delegator()
        clientB.delegate = delegatorB
        delegatorB.conversationEvent = { client, conv, event in
            switch event {
            case .joined(byClientID: _):
                getEventsExp.fulfill()
            case .membersJoined(members: _, byClientID: _):
                getEventsExp.fulfill()
            default:
                break
            }
        }
        NotificationCenter.default.addObserver(forName: IMClient.TestGetOfflineEventsNotification, object: clientB, queue: OperationQueue.main) { (notification) in
            XCTAssertTrue(((notification.userInfo?["serverTimestamp"] as? Int64) ?? -1) > 0)
            getEventsExp.fulfill()
        }
        clientB.connection.connect()
        wait(for: [getEventsExp], timeout: timeout)
        
        XCTAssertEqual(clientA.convCollection.count, 1)
        XCTAssertEqual(clientB.convCollection.count, 1)
        XCTAssertEqual(clientA.convCollection.first?.value.ID, clientB.convCollection.first?.value.ID)
        XCTAssertEqual(clientA.localRecord.lastServerTimestamp, clientB.localRecord.lastServerTimestamp)
    }
    
}

extension IMConversationTestCase {
    
    func newOpenedClient(clientID: String? = nil, customRTMURL: URL? = nil) -> IMClient? {
        var client: IMClient? = try? IMClient(ID: clientID ?? uuid, customServerURL: customRTMURL)
        let exp = expectation(description: "open")
        client?.open { (result) in
            if result.isFailure { client = nil }
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        return client
    }
    
    static func newServiceConversation() -> String? {
        var objectID: String?
        let parameters: Parameters = [
            "name": uuid
        ]
        let headers: HTTPHeaders = [
            "X-LC-Id": LCApplication.default.id,
            "X-LC-Key": LCApplication.default.key,
            "Content-Type": "application/json"
        ]
        let request: URLRequest = Alamofire.request(
            v2Router.route(path: "/rtm/service-conversations", module: .api)!,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers
            ).request!
        print("------\n\(request.url!)\n\(parameters)\n------\n")
        var loop = true
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            XCTAssertTrue((200..<300).contains(statusCode))
            if let data = data,
                let object = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) as [String : Any]??),
                let json: [String: Any] = object {
                print("------\n\(json)\n------\n")
                objectID = json["objectId"] as? String
            }
            loop = false
        }
        task.resume()
        while loop {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        return objectID
    }
    
    static func subscribing(serviceConversation conversationID: String, by clientID: String) -> Bool {
        var success: Bool = false
        let parameters: Parameters = [
            "client_id": clientID
        ]
        let headers: HTTPHeaders = [
            "X-LC-Id": LCApplication.default.id,
            "X-LC-Key": masterKey,
            "Content-Type": "application/json"
        ]
        let request: URLRequest = Alamofire.request(
            v2Router.route(path: "/rtm/service-conversations/\(conversationID)/subscribers")!,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers
            ).request!
        print("------\n\(request.url!)\n\(parameters)\n------\n")
        var loop = true
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(statusCode) {
                success = true
            } else {
                XCTFail()
            }
            if let data = data,
                let object = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) as [String : Any]??),
                let json: [String: Any] = object {
                print("------\n\(json)\n------\n")
            }
            loop = false
        }
        task.resume()
        while loop {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        return success
    }
    
    static func broadcastingMessage(to conversationID: String, content: String = "test") -> (String, Int64)? {
        var tuple: (String, Int64)?
        let parameters: Parameters = [
            "from_client": "master",
            "message": content
        ]
        let headers: HTTPHeaders = [
            "X-LC-Id": LCApplication.default.id,
            "X-LC-Key": masterKey,
            "Content-Type": "application/json"
        ]
        let request: URLRequest = Alamofire.request(
            v2Router.route(path: "/rtm/service-conversations/\(conversationID)/broadcasts", module: .api)!,
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers
            ).request!
        print("------\n\(request.url!)\n\(parameters)\n------\n")
        var loop = true
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            XCTAssertTrue((200..<300).contains(statusCode))
            if let data = data,
                let object = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) as [String : Any]??),
                let json: [String: Any] = object {
                print("------\n\(json)\n------\n")
                if let result: [String: Any] = json["result"] as? [String: Any],
                    let messageID = result["msg-id"] as? String,
                    let timestamp: Int64 = result["timestamp"] as? Int64 {
                    tuple = (messageID, timestamp)
                }
            }
            loop = false
        }
        task.resume()
        while loop {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        return tuple
    }
    
}
