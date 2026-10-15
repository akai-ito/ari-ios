import AriKit
import CryptoKit
import Foundation
import Testing

@Suite("Notifications")
struct PushTests {
    @Test(
        "every push in the transcripts decodes as a notification",
        arguments: try Fixtures.transcripts())
    func pushes(_ transcript: Transcript) throws {
        for case .push(let push) in transcript.steps {
            let notification = try #require(push.json["notification"]).decode(PushNotification.self)
            let place = "\(transcript.name).jsonl line \(push.line)"
            #expect(notification.kind.isKnown && !notification.text.isEmpty, "\(place)")
            if notification.kind == .ask || notification.kind == .reminder {
                #expect(notification.ask != nil, "\(place)")
            }
            if notification.kind == .reply { #expect(notification.message != nil, "\(place)") }
        }
    }

    @Test("a sealed notification opens with the key that sealed it, and only with the device's id")
    func opens() throws {
        let key = NotificationKey()
        let old = NotificationKey()
        let device = "545b5899-36cc-430d-9929-31d5e4f3bb14"
        let json = Data(
            #"{"kind":"ask","text":"Which Juno did you mean?","ask":{"id":"a_1","options":["Clapham","Soho"],"allows_text":true,"secret":false}}"#
                .utf8)
        let sealed = try seal(json, with: key, device: device)
        let payload: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Ari", "body": "Ari asked you something"]],
            "ito": ["v": sealed.v, "k": sealed.k, "n": sealed.n, "c": sealed.c],
        ]
        let read = try #require(SealedNotification(payload: payload))
        let notification = try read.open(with: [old, key], device: device)
        #expect(notification.kind == .ask && notification.ask?.options == ["Clapham", "Soho"])
        #expect(throws: NotificationError.unknownKey) { try read.open(with: [old], device: device) }
        #expect(throws: NotificationError.unreadable) {
            try read.open(with: [key], device: "another-device")
        }
    }

    @Test("a key is 256 bits, travels as base64, and is named as the server names it")
    func keys() throws {
        // Scenario 26 registers a key, and the server answers with that key's id.
        var registered: NotificationKey?
        var named: String?
        for step in try Fixtures.transcript("26-turning-on-notifications").steps {
            if case .app(let request) = step, request.route == .device,
                let body = try request.body?.decode(RegisterDevice.self)
            {
                registered = NotificationKey(base64: body.notificationKey)
            }
            if case .server(let response) = step, registered != nil, named == nil,
                let result = try? response.body?.decode(DeviceResult.self)
            {
                named = result.device.keyID
            }
        }
        let key = try #require(registered)
        #expect(key.id == named)
        #expect(NotificationKey(base64: key.base64) == key)
        #expect(NotificationKey(base64: "c2hvcnQ=") == nil)
        #expect(NotificationKey().data.count == 32)
    }

    /// Seals as the server does: AES-256-GCM, a random 12-byte nonce, the tag after the
    /// ciphertext, and the device's id as additional data.
    private func seal(_ json: Data, with key: NotificationKey, device: String) throws
        -> SealedNotification
    {
        let box = try AES.GCM.seal(
            json, using: SymmetricKey(data: key.data), authenticating: Data(device.utf8))
        let payload: [AnyHashable: Any] = [
            "ito": [
                "v": 1, "k": key.id, "n": Data(box.nonce).base64EncodedString(),
                "c": (box.ciphertext + box.tag).base64EncodedString(),
            ]
        ]
        return try #require(SealedNotification(payload: payload))
    }
}
