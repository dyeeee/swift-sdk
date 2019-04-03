//
//  File.swift
//  LeanCloud
//
//  Created by Tianyong Tang on 2018/9/19.
//  Copyright © 2018 LeanCloud. All rights reserved.
//

import Foundation

/**
 LeanCloud file type.
 */
public class LCFile: LCObject {

    /// The file URL.
    @objc dynamic public var url: LCString?

    /**
     The file key.

     It's the resource key of third-party file hosting provider.
     It may be nil for some providers.
     */
    @objc dynamic public var key: LCString?

    /// The file name.
    @objc dynamic public var name: LCString?

    /// The file meta data.
    @objc dynamic public var metaData: LCDictionary?

    /// The file hosting provider.
    @objc dynamic public var provider: LCString?

    /// The file bucket.
    @objc dynamic public var bucket: LCString?

    /**
     The MIME type of file.

     For uploading, you can use this property to explictly set MIME type of file content.

     It's an alias of property 'mime_type'.
     */
    public var mimeType: LCString? {
        get {
            return self.get("mime_type") as? LCString
        }
        set {
            try? self.set("mime_type", value: newValue)
        }
    }

    /// The HTTP client.
    private lazy var httpClient = HTTPClient.default

    public required init() {
        super.init()
    }

    /**
     Create file with URL.

     - parameter url: The file URL.
     */
    public init(url: LCStringConvertible) {
        super.init()
        self.url = url.lcString
    }

    /**
     The file payload.

     This type represents a resource to be uploaded.
     */
    public enum Payload {

        /// File content represented by data.
        case data(data: Data)

        /// File content represented by file URL.
        case fileURL(fileURL: URL)

    }

    /// The payload to be uploaded.
    private(set) var payload: Payload?

    /**
     Create file with content.

     - parameter content: The file content.
     */
    public init(payload: Payload) {
        super.init()
        self.payload = payload
    }

    public final override class func objectClassName() -> String {
        return "_File"
    }

    public override func save() -> LCBooleanResult {
        return expect { fulfill in
            self.save(
            progressInBackground: { _ in /* Nop */ },
            completion: { result in
                fulfill(result)
            })
        }
    }

    public override func save(
        _ completion: @escaping (LCBooleanResult) -> Void) -> LCRequest
    {
        return save(
            progress: { _ in /* Nop */ },
            completion: completion)
    }

    /**
     Save current file.

     - parameter progress: The progress handler.
     - parameter completion: The completion handler.

     - returns: The request of saving.
     */
    public func save(
        progress: @escaping (Double) -> Void,
        completion: @escaping (LCBooleanResult) -> Void) -> LCRequest
    {
        return save(
        progressInBackground: { value in
            mainQueueAsync {
                progress(value)
            }
        },
        completion: { result in
            mainQueueAsync {
                completion(result)
            }
        })
    }

    /**
     Save current file and call handler in background thread.

     - parameter progress: The progress handler.
     - parameter completion: The completion handler.

     - returns: The request of saving.
     */
    @discardableResult
    private func save(
        progressInBackground progress: @escaping (Double) -> Void,
        completion: @escaping (LCBooleanResult) -> Void) -> LCRequest
    {
        if let _ = objectId {
            let error = LCError(
                code: .inconsistency,
                reason: "Cannot update file after it has been saved.")

            return httpClient.request(error: error) { result in
                completion(result)
            }
        }

        if let payload = payload {
            return upload(payload: payload, progress: progress, completion: { result in
                self.handleUploadResult(result, completion: completion)
            })
        } else if let _ = url {
            let parameters = dictionary.jsonValue as? [String: Any]

            return httpClient.request(.post, "files", parameters: parameters) { response in
                let result = LCValueResult<LCDictionary>(response: response)
                self.handleSaveResult(result, completion: completion)
            }
        } else {
            let error = LCError(code: .notFound, reason: "No payload or URL to upload.")

            return httpClient.request(error: error) { result in
                completion(result)
            }
        }
    }

    /**
     Upload payload.

     - parameter payload: The payload to be uploaded.
     - parameter progress: The progress handler.
     - parameter completion: The completion handler.

     - returns: The uploading request.
     */
    private func upload(
        payload: Payload,
        progress: @escaping (Double) -> Void,
        completion: @escaping (LCBooleanResult) -> Void) -> LCRequest
    {
        let uploader = FileUploader(file: self, payload: payload)

        return uploader.upload(
            progress: progress,
            completion: completion)
    }

    /**
     Handle result for payload uploading.

     If result is successful, it will discard changes.

     - parameter result: The save result.
     - parameter completion: The completion closure.
     */
    private func handleUploadResult(
        _ result: LCBooleanResult,
        completion: (LCBooleanResult) -> Void)
    {
        switch result {
        case .success:
            discardChanges()
        case .failure:
            break
        }
        completion(result)
    }

    /**
     Handle result for saving.

     If result is successful, it will discard changes.

     - parameter result: The save result.
     - parameter completion: The completion closure.
     */
    private func handleSaveResult(
        _ result: LCValueResult<LCDictionary>,
        completion: (LCBooleanResult) -> Void)
    {
        switch result {
        case .success(let dictionary):
            dictionary.forEach { (key, value) in
                update(key, value)
            }
            discardChanges()
            completion(.success)
        case .failure(let error):
            completion(.failure(error: error))
        }
    }

}
