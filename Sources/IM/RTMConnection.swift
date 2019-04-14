//
//  RTMConnection.swift
//  LeanCloud
//
//  Created by zapcannon87 on 2018/10/17.
//  Copyright © 2018 LeanCloud. All rights reserved.
//

import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif
import Starscream
import Alamofire

public var RTMConnectingTimeoutInterval: TimeInterval = 10.0
public var RTMTimeoutInterval: TimeInterval = 30.0

private let RTMMutex = NSLock()

var RTMConnectionRefMap_protobuf1: [String: [String: RTMConnection]] = [:]
var RTMConnectionRefMap_protobuf3: [String: [String: RTMConnection]] = [:]

func RTMConnectionRegistering(
    application: LCApplication,
    peerID: String,
    lcimProtocol: RTMConnection.LCIMProtocol,
    customServerURL: URL? = nil)
    throws -> RTMConnection
{
    RTMMutex.lock()
    defer { RTMMutex.unlock() }
    
    var connectionRefMap: [String: [String: RTMConnection]]
    switch lcimProtocol {
    case .protobuf1:
        connectionRefMap = RTMConnectionRefMap_protobuf1
    case .protobuf3:
        connectionRefMap = RTMConnectionRefMap_protobuf3
    }
    
    let appID: String = application.id
    let connection: RTMConnection
    
    if var sharedConnectionMap: [String: RTMConnection] = connectionRefMap[appID] {
        if let _ = sharedConnectionMap[peerID] {
            throw LCError(
                code: .inconsistency,
                reason:
                """
                \(#file): duplicate registered.
                
                The RTM Connection which use \(lcimProtocol.rawValue) has been referred by one exist instance,
                That instance's Application-ID is \(appID) and Peer-ID is \(peerID).
                
                Suggestion: Releasing that instance or Using other `Application-ID + Peer-ID` to register.
                """
            )
        } else {
            if let existConnection: RTMConnection = sharedConnectionMap.values.first {
                connection = existConnection
                sharedConnectionMap[peerID] = connection
            } else {
                connection = try RTMConnection(
                    application: application,
                    lcimProtocol: lcimProtocol,
                    customRTMServerURL: customServerURL
                )
                sharedConnectionMap[peerID] = connection
            }
            connectionRefMap[appID] = sharedConnectionMap
        }
    } else {
        connection = try RTMConnection(
            application: application,
            lcimProtocol: lcimProtocol,
            customRTMServerURL: customServerURL
        )
        connectionRefMap[appID] = [peerID: connection]
    }
    
    switch lcimProtocol {
    case .protobuf1:
        RTMConnectionRefMap_protobuf1 = connectionRefMap
    case .protobuf3:
        RTMConnectionRefMap_protobuf3 = connectionRefMap
    }
    
    return connection
}

func RTMConnectionReleasing(
    application: LCApplication,
    peerID: String,
    lcimProtocol: RTMConnection.LCIMProtocol)
{
    RTMMutex.lock()
    defer { RTMMutex.unlock() }
    
    var connectionRefMap: [String: [String: RTMConnection]]
    switch lcimProtocol {
    case .protobuf1:
        connectionRefMap = RTMConnectionRefMap_protobuf1
    case .protobuf3:
        connectionRefMap = RTMConnectionRefMap_protobuf3
    }
    
    let appID: String = application.id
    
    if var sharedConnectionMap: [String: RTMConnection] = connectionRefMap[appID] {
        sharedConnectionMap.removeValue(forKey: peerID)
        connectionRefMap[appID] = sharedConnectionMap
        switch lcimProtocol {
        case .protobuf1:
            RTMConnectionRefMap_protobuf1 = connectionRefMap
        case .protobuf3:
            RTMConnectionRefMap_protobuf3 = connectionRefMap
        }
    }
}

protocol RTMConnectionDelegate: class {

    func connection(inConnecting connection: RTMConnection)
    
    func connection(didConnect connection: RTMConnection)
    
    func connection(_ connection: RTMConnection, didDisconnect error: LCError)
    
    func connection(_ connection: RTMConnection, didReceiveCommand inCommand: IMGenericCommand)
}

class RTMConnection {
    
    #if DEBUG
    static let TestGoawayCommandReceivedNotification = Notification.Name("\(RTMConnection.self).TestGoawayCommandReceivedNotification")
    #endif
    
    /// ref: https://github.com/leancloud/avoscloud-push/blob/develop/push-server/doc/protocol.md#传输协议
    enum LCIMProtocol: String {
        case protobuf1 = "lc.protobuf2.1"
        case protobuf3 = "lc.protobuf2.3"
    }
    
    class CommandCallback {
        enum Result {
            case inCommand(IMGenericCommand)
            case error(LCError)
            
            var command: IMGenericCommand? {
                switch self {
                case .inCommand(let command):
                    return command
                case .error:
                    return nil
                }
            }
            
            var error: LCError? {
                switch self {
                case .inCommand:
                    return nil
                case .error(let error):
                    return error
                }
            }
        }
        
        let closure: (Result) -> Void
        let expiration: TimeInterval
        let callingQueue: DispatchQueue
        
        init(callingQueue: DispatchQueue, closure: @escaping (Result) -> Void) {
            self.closure = closure
            self.expiration = Date().timeIntervalSince1970 + RTMTimeoutInterval
            self.callingQueue = callingQueue
        }
    }
    
    class Timer {
        
        let pingpongInterval: TimeInterval = 180.0
        let pingTimeout: TimeInterval = 20.0
        let source: DispatchSourceTimer
        let socket: WebSocketClient
        private(set) var commandIndexSequence: [UInt16] = []
        private(set) var commandCallbackCollection: [UInt16 : CommandCallback] = [:]
        private(set) var lastPingSentTimestamp: TimeInterval = 0
        private(set) var lastPongReceivedTimestamp: TimeInterval = 0
        
        #if DEBUG
        private(set) var specificKey: DispatchSpecificKey<Int>? = nil
        private(set) var specificValue: Int? = nil
        private var specificAssertion: Bool {
            if let key = self.specificKey, let value = self.specificValue {
                return DispatchQueue.getSpecific(key: key) == value
            } else {
                return false
            }
        }
        #else
        private var specificAssertion: Bool {
            return true
        }
        #endif
        
        init(connection: RTMConnection, socket: WebSocketClient) {
            #if DEBUG
            self.specificKey = connection.specificKey
            self.specificValue = connection.specificValue
            #endif
            self.source = DispatchSource.makeTimerSource(queue: connection.serialQueue)
            self.socket = socket
            self.source.schedule(deadline: .now(), repeating: .seconds(1))
            self.source.setEventHandler { [weak self] in
                let currentTimestamp: TimeInterval = Date().timeIntervalSince1970
                self?.check(commandTimeout: currentTimestamp)
                self?.check(pingPong: currentTimestamp)
            }
            self.source.resume()
        }
        
        deinit {
            self.source.cancel()
            let values = self.commandCallbackCollection.values
            if values.count > 0 {
                let error = LCError(code: .connectionLost)
                for item in values {
                    item.callingQueue.async {
                        item.closure(.error(error))
                    }
                }
            }
        }
        
        func insert(commandCallback: CommandCallback, index: UInt16) {
            assert(self.specificAssertion)
            self.commandIndexSequence.append(index)
            self.commandCallbackCollection[index] = commandCallback
        }
        
        func handle(callbackCommand command: IMGenericCommand) {
            assert(self.specificAssertion)
            let i: Int32 = (command.hasI ? command.i : 0)
            guard i > 0 && i <= UInt16.max else {
                Logger.shared.error("unexpected index<\(command.i)> of command has been found.")
                return
            }
            let indexKey: UInt16 = UInt16(i)
            guard let commandCallback: CommandCallback = self.commandCallbackCollection.removeValue(forKey: indexKey) else {
                Logger.shared.error("not found callback for in command with index<\(indexKey)>.")
                return
            }
            if let index: Int = self.commandIndexSequence.firstIndex(of: indexKey) {
                self.commandIndexSequence.remove(at: index)
            }
            commandCallback.callingQueue.async {
                if let error: LCError = command.encounteredError {
                    commandCallback.closure(.error(error))
                } else {
                    commandCallback.closure(.inCommand(command))
                }
            }
        }
        
        private func check(commandTimeout currentTimestamp: TimeInterval) {
            assert(self.specificAssertion)
            var length: Int = 0
            for indexKey in self.commandIndexSequence {
                length += 1
                guard let commandCallback: CommandCallback = self.commandCallbackCollection[indexKey] else {
                    continue
                }
                if commandCallback.expiration > currentTimestamp  {
                    length -= 1
                    break
                } else {
                    self.commandCallbackCollection.removeValue(forKey: indexKey)
                    commandCallback.callingQueue.async {
                        let error = LCError(code: .commandTimeout)
                        commandCallback.closure(.error(error))
                    }
                }
            }
            if length > 0 {
                self.commandIndexSequence.removeSubrange(0..<length)
            }
        }
        
        private func check(pingPong currentTimestamp: TimeInterval) {
            assert(self.specificAssertion)
            let isPingSentAndPongNotReceived: Bool = (self.lastPingSentTimestamp > self.lastPongReceivedTimestamp)
            let lastPingTimeout: Bool = (isPingSentAndPongNotReceived && currentTimestamp > self.lastPingSentTimestamp + self.pingTimeout)
            let shouldNextPingPong: Bool = (!isPingSentAndPongNotReceived && currentTimestamp > self.lastPongReceivedTimestamp + self.pingpongInterval)
            if lastPingTimeout || shouldNextPingPong {
                self.socket.write(ping: Data()) {
                    Logger.shared.verbose("\(self.socket) ping sent")
                }
                self.lastPingSentTimestamp = currentTimestamp
            }
        }
        
        func receivePong() {
            assert(self.specificAssertion)
            Logger.shared.verbose("\(self.socket) pong received")
            self.lastPongReceivedTimestamp = Date().timeIntervalSince1970
        }
        
    }
    
    class Delegator {
        let queue: DispatchQueue
        weak var delegate: RTMConnectionDelegate? = nil
        
        init(queue: DispatchQueue) {
            self.queue = queue
        }
    }
    
    enum DelayInterval: Int {
        case second1 = 1
        case second2 = 2
        case second4 = 4
        case second8 = 8
        case second16 = 16
        case secondMax = 30
        
        init(doubling delay: DelayInterval) {
            let doubledSecond = (delay.rawValue * 2)
            if let value = DelayInterval(rawValue: doubledSecond) {
                self = value
            } else {
                self = .secondMax
            }
        }
    }
    
    let application: LCApplication
    let lcimProtocol: LCIMProtocol
    let customRTMServerURL: URL?
    let rtmRouter: RTMRouter?
    
    let serialQueue: DispatchQueue = DispatchQueue(label: "\(RTMConnection.self).serialQueue")
    
    private(set) var delegatorMap: [String: Delegator] = [:]
    private(set) var socket: WebSocket? = nil
    private(set) var timer: Timer? = nil
    private(set) var previousConnectingWorkItem: DispatchWorkItem?
    private(set) var useSecondaryServer: Bool = false
    private(set) var reconnectingDelay: DelayInterval = .second1
    private(set) var isInRouting: Bool = false
    
    private var nextSerialIndex: UInt16 {
        let index: UInt16 = self.underlyingSerialIndex
        if index == UInt16.max {
            self.underlyingSerialIndex = 1
        } else {
            self.underlyingSerialIndex += 1
        }
        return index
    }
    private(set) var underlyingSerialIndex: UInt16 = 1
    
    #if os(iOS) || os(tvOS)
    enum AppState {
        case background
        case foreground
    }
    private(set) var previousAppState: AppState = .foreground
    private(set) var enterBackgroundObserver: NSObjectProtocol?
    private(set) var enterForegroundObserver: NSObjectProtocol?
    #endif
    
    #if !os(watchOS)
    private(set) var previousReachabilityStatus: NetworkReachabilityManager.NetworkReachabilityStatus = .unknown
    private(set) var reachabilityManager: NetworkReachabilityManager? = nil
    #endif
    
    #if DEBUG
    let specificKey = DispatchSpecificKey<Int>()
    let specificValue: Int = Int.random(in: 100...999) // whatever random int is OK.
    private var specificAssertion: Bool {
        return self.specificValue == DispatchQueue.getSpecific(key: self.specificKey)
    }
    #else
    private var specificAssertion: Bool {
        return true
    }
    #endif
    
    init(application: LCApplication, lcimProtocol: LCIMProtocol, customRTMServerURL: URL? = nil) throws {
        #if DEBUG
        self.serialQueue.setSpecific(key: self.specificKey, value: self.specificValue)
        #endif
        
        self.application = application
        self.lcimProtocol = lcimProtocol
        if let customRTMServerURL = customRTMServerURL {
            self.customRTMServerURL = customRTMServerURL
            self.rtmRouter = nil
        } else {
            self.customRTMServerURL = nil
            self.rtmRouter = try RTMRouter(application: application)
        }
        
        #if os(iOS) || os(tvOS)
        self.previousAppState = mainQueueSync {
            (UIApplication.shared.applicationState == .background ? .background : .foreground)
        }
        let operationQueue = OperationQueue()
        operationQueue.underlyingQueue = self.serialQueue
        self.enterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: operationQueue)
        { [weak self] _ in
            Logger.shared.verbose("Application did enter background")
            self?.applicationStateChanged(with: .background)
        }
        self.enterForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: operationQueue)
        { [weak self] _ in
            Logger.shared.verbose("Application will enter foreground")
            self?.applicationStateChanged(with: .foreground)
        }
        #endif
        
        #if !os(watchOS)
        self.reachabilityManager = NetworkReachabilityManager()
        self.previousReachabilityStatus = self.reachabilityManager?.networkReachabilityStatus ?? .unknown
        self.reachabilityManager?.listenerQueue = self.serialQueue
        self.reachabilityManager?.listener = { [weak self] newStatus in
            Logger.shared.verbose("Network status change to \(newStatus)")
            self?.networkReachabilityStatusChanged(with: newStatus)
        }
        self.reachabilityManager?.startListening()
        #endif
    }
    
    deinit {
        #if os(iOS) || os(tvOS)
        if let observer = self.enterBackgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = self.enterForegroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
        
        #if !os(watchOS)
        self.reachabilityManager?.stopListening()
        #endif
        
        self.socket?.disconnect()
    }
    
    func removeDelegator(peerID: String) {
        self.serialQueue.async {
            self.delegatorMap.removeValue(forKey: peerID)
        }
    }
    
    func connect(peerID: String? = nil, delegator: Delegator? = nil) {
        self.serialQueue.async {
            if let peerID = peerID, let delegator = delegator {
                self.delegatorMap[peerID] = delegator
            }
            if let _ = self.socket, let _ = self.timer {
                delegator?.queue.async {
                    delegator?.delegate?.connection(didConnect: self)
                }
            } else if self.socket == nil, self.timer == nil {
                if let error: LCError = self.checkEnvironment() {
                    delegator?.queue.async {
                        delegator?.delegate?.connection(self, didDisconnect: error)
                    }
                } else {
                    self.tryConnecting()
                }
            } else {
                // means in connecting, just wait.
            }
        }
    }
    
    func disconnect() {
        self.serialQueue.async {
            self.tryClearConnection(with: LCError.RTMConnectionClosedByLocal)
        }
    }
    
    func send(
        command: IMGenericCommand,
        callingQueue: DispatchQueue? = nil,
        callback: ((CommandCallback.Result) -> Void)? = nil)
    {
        self.serialQueue.async {
            guard let socket: WebSocket = self.socket, let timer: Timer = self.timer else {
                callingQueue?.async {
                    let error = LCError(code: .connectionLost)
                    callback?(.error(error))
                }
                return
            }
            var outCommand = command
            if callback != nil {
                outCommand.i = Int32(self.nextSerialIndex)
            }
            let serializedData: Data
            do {
                serializedData = try outCommand.serializedData()
            } catch {
                Logger.shared.error(error)
                callingQueue?.async {
                    let serializingError = LCError(error: error)
                    callback?(.error(serializingError))
                }
                return
            }
            guard serializedData.count <= 5000 else {
                callingQueue?.async {
                    let error = LCError(code: .commandDataLengthTooLong)
                    callback?(.error(error))
                }
                return
            }
            if let callback = callback, let callingQueue = callingQueue {
                let commandCallback = CommandCallback(callingQueue: callingQueue, closure: callback)
                let index: UInt16 = UInt16(outCommand.i)
                timer.insert(commandCallback: commandCallback, index: index)
            }
            socket.write(data: serializedData) {
                Logger.shared.debug("\n\n------ BEGIN LeanCloud Out Command\n\(socket)\n\(outCommand)------ END\n")
            }
        }
    }
    
}

// MARK: - Private

extension RTMConnection {
    
    #if os(iOS) || os(tvOS)
    private func applicationStateChanged(with newState: RTMConnection.AppState) {
        assert(self.specificAssertion)
        let oldState: AppState = self.previousAppState
        self.previousAppState = newState
        switch (oldState, newState) {
        case (.background, .foreground):
            self.tryConnecting()
        case (.foreground, .background):
            self.tryClearConnection(with: LCError.RTMConnectionAppInBackground)
            self.reconnectingDelay = .second1
        default:
            break
        }
    }
    #endif
    
    #if !os(watchOS)
    private func networkReachabilityStatusChanged(with newStatus: NetworkReachabilityManager.NetworkReachabilityStatus) {
        assert(self.specificAssertion)
        let oldStatus = self.previousReachabilityStatus
        self.previousReachabilityStatus = newStatus
        if oldStatus != .notReachable && newStatus == .notReachable {
            self.tryClearConnection(with: LCError.RTMConnectionNetworkUnavailable)
            self.reconnectingDelay = .second1
        } else if oldStatus != newStatus && newStatus != .notReachable {
            self.tryClearConnection(with: LCError.RTMConnectionNetworkChanged)
            self.reconnectingDelay = .second1
            self.tryConnecting()
        }
    }
    #endif
    
    private func checkEnvironment() -> LCError? {
        assert(self.specificAssertion)
        #if os(iOS) || os(tvOS)
        guard self.previousAppState == .foreground else {
            return LCError.RTMConnectionAppInBackground
        }
        #endif
        #if !os(watchOS)
        guard self.previousReachabilityStatus != .notReachable else {
            return LCError.RTMConnectionNetworkUnavailable
        }
        #endif
        return nil
    }
    
    private func canConnecting() -> Bool {
        assert(self.specificAssertion)
        if
            (self.socket == nil),
            (!self.delegatorMap.isEmpty),
            (self.checkEnvironment() == nil)
        {
            return true
        } else {
            return false
        }
    }
    
    private func connectingWorkItem() -> DispatchWorkItem {
        return DispatchWorkItem { [weak self] in
            self?.previousConnectingWorkItem = nil
            self?.getRTMServer { (result: LCGenericResult<URL>) in
                guard let self = self else {
                    return
                }
                assert(self.specificAssertion)
                guard self.canConnecting() else {
                    return
                }
                switch result {
                case .success(value: let url):
                    var request = URLRequest(url: url)
                    request.timeoutInterval = RTMConnectingTimeoutInterval
                    let socket = WebSocket(request: request, protocols: [self.lcimProtocol.rawValue])
                    socket.delegate = self
                    socket.pongDelegate = self
                    socket.callbackQueue = self.serialQueue
                    socket.connect()
                    self.socket = socket
                    Logger.shared.verbose("\(socket) connecting URL<\"\(url)\"> with protocol<\"\(self.lcimProtocol.rawValue)\">")
                case .failure(error: let error):
                    for item in self.delegatorMap.values {
                        item.queue.async {
                            item.delegate?.connection(self, didDisconnect: error)
                        }
                    }
                    self.tryConnecting(delay: self.reconnectingDelay)
                    Logger.shared.error("Get RTM server URL failed: \(error)")
                }
            }
        }
    }
    
    private func tryConnecting(delay: DelayInterval? = nil) {
        assert(self.specificAssertion)
        
        guard self.canConnecting() else {
            return
        }
        
        self.previousConnectingWorkItem?.cancel()
        let workItem: DispatchWorkItem = self.connectingWorkItem()
        self.previousConnectingWorkItem = workItem
        
        for item in self.delegatorMap.values {
            item.queue.async {
                item.delegate?.connection(inConnecting: self)
            }
        }
        
        if let delay: DelayInterval = delay {
            self.serialQueue.asyncAfter(
                deadline: .now() + .seconds(delay.rawValue),
                execute: workItem
            )
            self.reconnectingDelay = DelayInterval(doubling: delay)
            self.rtmRouter?.updateFailureCount()
        } else {
            workItem.perform()
        }
    }
    
    private func tryClearConnection(with error: LCError) {
        assert(self.specificAssertion)
        if let workItem = self.previousConnectingWorkItem {
            workItem.cancel()
            self.previousConnectingWorkItem = nil
        }
        if let socket = self.socket {
            socket.delegate = nil
            socket.pongDelegate = nil
            socket.disconnect()
            self.socket = nil
        }
        for item in self.delegatorMap.values {
            item.queue.async {
                item.delegate?.connection(self, didDisconnect: error)
            }
        }
        self.timer = nil
    }
    
    private func getRTMServer(callback: @escaping (LCGenericResult<URL>) -> Void) {
        assert(self.specificAssertion)
        if let customRTMServerURL = self.customRTMServerURL {
            callback(.success(value: customRTMServerURL))
        } else if let rtmRouter = self.rtmRouter, !self.isInRouting {
            self.isInRouting = true
            rtmRouter.route { [weak self] (direct, result) in
                guard let self = self else {
                    return
                }
                let completion: () -> Void = {
                    self.isInRouting = false
                    switch result {
                    case .success(value: let table):
                        if let url: URL = (self.useSecondaryServer ? table.secondaryURL : table.primaryURL) ?? table.primaryURL {
                            callback(.success(value: url))
                        } else {
                            callback(.failure(error: LCError.RTMRouterResponseDataMalformed))
                        }
                    case .failure(error: let error):
                        let routerError = LCError.RTMRouterResponseDataMalformed
                        if error.code == routerError.code, error.reason == routerError.reason {
                            self.delegatorMap.removeAll()
                            self.tryClearConnection(with: error)
                        } else {
                            callback(.failure(error: error))
                        }
                    }
                }
                if direct {
                    completion()
                } else {
                    self.serialQueue.async { completion() }
                }
            }
        }
    }
    
    private func handleGoaway(inCommand: IMGenericCommand) {
        assert(self.specificAssertion)
        guard
            inCommand.cmd == .goaway,
            let rtmRouter = self.rtmRouter
            else
        {
            return
        }
        rtmRouter.clearTableCache()
        self.tryClearConnection(with: LCError.RTMConnectionClosedByRemote)
        self.tryConnecting()
        #if DEBUG
        NotificationCenter.default.post(
            name: RTMConnection.TestGoawayCommandReceivedNotification,
            object: self
        )
        #endif
    }
    
}

// MARK: - WebSocketDelegate

extension RTMConnection: WebSocketDelegate, WebSocketPongDelegate {
    
    func websocketDidConnect(socket: WebSocketClient) {
        assert(self.specificAssertion)
        assert(self.socket === socket && self.timer == nil)
        Logger.shared.verbose("\(socket) connect success")
        self.reconnectingDelay = .second1
        self.rtmRouter?.updateFailureCount(reset: true)
        self.timer = Timer(connection: self, socket: socket)
        for item in self.delegatorMap.values {
            item.queue.async {
                item.delegate?.connection(didConnect: self)
            }
        }
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        assert(self.specificAssertion)
        assert(self.socket === socket)
        Logger.shared.error("\(socket) disconnect with error: \(String(describing: error))")
        self.tryClearConnection(with: LCError(error: error ?? LCError.RTMConnectionClosedByRemote))
        self.useSecondaryServer.toggle()
        self.tryConnecting(delay: self.reconnectingDelay)
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        assert(self.specificAssertion)
        assert(self.socket === socket && self.timer != nil)
        let inCommand: IMGenericCommand
        do {
            inCommand = try IMGenericCommand(serializedData: data)
        } catch {
            Logger.shared.error(error)
            return
        }
        Logger.shared.debug("\n\n------ BEGIN LeanCloud In Command\n\(socket)\n\(inCommand)------ END\n")
        if inCommand.hasI {
            self.timer?.handle(callbackCommand: inCommand)
        } else {
            if inCommand.hasPeerID {
                let peerID = inCommand.peerID
                if let delegator: Delegator = self.delegatorMap[peerID] {
                    delegator.queue.async {
                        delegator.delegate?.connection(self, didReceiveCommand: inCommand)
                    }
                } else {
                    Logger.shared.error("\(type(of: self)) not found delegator for peer ID: \(peerID)")
                }
            } else {
                self.handleGoaway(inCommand: inCommand)
            }
        }
    }
    
    func websocketDidReceivePong(socket: WebSocketClient, data: Data?) {
        assert(self.specificAssertion)
        assert(self.socket === socket && self.timer != nil)
        self.timer?.receivePong()
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        fatalError("should never be invoked.")
    }
    
}

extension IMGenericCommand {
    
    fileprivate var encounteredError: LCError? {
        if self.cmd == .error {
            if self.hasErrorMessage {
                return self.errorMessage.lcError
            } else {
                return LCError(code: .commandInvalid)
            }
        } else {
            return nil
        }
    }
    
}

extension IMErrorCommand {
    
    var lcError: LCError {
        let code: Int = Int(self.code)
        let reason: String? = (self.hasReason ? self.reason : nil)
        var userInfo: LCError.UserInfo? = [:]
        if self.hasAppCode {
            userInfo?["appCode"] = self.appCode
        }
        if self.hasAppMsg {
            userInfo?["appMsg"] = self.appMsg
        }
        if self.hasDetail {
            userInfo?["detail"] = self.detail
        }
        if let ui = userInfo, ui.isEmpty {
            userInfo = nil
        } else {
            do {
                userInfo = try userInfo?.jsonObject()
            } catch {
                Logger.shared.error(error)
                userInfo = nil
            }
        }
        let error = LCError(code: code, reason: reason, userInfo: userInfo)
        return error
    }
    
}

extension IMSessionCommand {
    
    var lcError: LCError {
        let code: Int = Int(self.code)
        let reason: String? = (self.hasReason ? self.reason : nil)
        var userInfo: LCError.UserInfo? = [:]
        if self.hasDetail {
            userInfo?["detail"] = self.detail
        }
        if let ui = userInfo, ui.isEmpty {
            userInfo = nil
        } else {
            do {
                userInfo = try userInfo?.jsonObject()
            } catch {
                Logger.shared.error(error)
                userInfo = nil
            }
        }
        let error = LCError(code: code, reason: reason, userInfo: userInfo)
        return error
    }
    
}

extension IMAckCommand {
    
    var lcError: LCError? {
        if self.hasCode || self.hasAppCode {
            let code: Int = Int(self.code)
            let reason: String? = (self.hasReason ? self.reason : nil)
            var userInfo: LCError.UserInfo? = [:]
            if self.hasAppCode {
                userInfo?["appCode"] = self.appCode
            }
            if self.hasAppMsg {
                userInfo?["appMsg"] = self.appMsg
            }
            if let ui = userInfo, ui.isEmpty {
                userInfo = nil
            } else {
                do {
                    userInfo = try userInfo?.jsonObject()
                } catch {
                    Logger.shared.error(error)
                    userInfo = nil
                }
            }
            let error = LCError(code: code, reason: reason, userInfo: userInfo)
            return error
        } else {
            return nil
        }
    }
    
}

extension LCError {
    
    static var RTMConnectionAppInBackground: LCError {
        return LCError(
            code: .connectionLost,
            reason: "\(#file): Due to application did enter background, connection lost."
        )
    }
    
    static var RTMConnectionNetworkUnavailable: LCError {
        return LCError(
            code: .connectionLost,
            reason: "\(#file): Due to network unavailable, connection lost."
        )
    }
    
    static var RTMConnectionNetworkChanged: LCError {
        return LCError(
            code: .connectionLost,
            reason: "\(#file): Due to network interface changed, connection lost."
        )
    }
    
    static var RTMConnectionClosedByLocal: LCError {
        return LCError(
            code: .connectionLost,
            reason: "\(#file): Connection did close by local peer."
        )
    }
    
    static var RTMConnectionClosedByRemote: LCError {
        return LCError(
            code: .connectionLost,
            reason: "\(#file): Connection did close by remote peer."
        )
    }
    
}
