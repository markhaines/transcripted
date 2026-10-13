import Foundation

/// A complete process-activity read, independent of the start detector's
/// sustain gates. nil means a failed read, never an ended call.
struct MeetingCallActivitySnapshot: Equatable {
    let inputUsers: Set<String>
    let outputUsers: Set<String>
    let isReliable: Bool
    var sampledAt: TimeInterval? = nil

    static let unknown = Self(inputUsers: [], outputUsers: [], isReliable: false)

    func sourceFamilies(detectedPrompt: Bool, provider: MeetingPromptProvider,
                        isBrowserCall: Bool, cameraOnly: Bool,
                        sampledAt: TimeInterval?, now: TimeInterval) -> Set<String>? {
        guard detectedPrompt, !cameraOnly, isReliable, let sampledAt,
              now >= sampledAt, now - sampledAt <= 12 else { return nil }
        if isBrowserCall {
            let families = Set(inputUsers.compactMap(MeetingPromptProvider.browserFamily(forBundleID:))
                .map(MeetingPromptProvider.browserAppFamily(forBundleFamily:)))
            guard families.count == 1 else { return nil }
            return families == ["com.apple.Safari"]
                ? ["com.apple.WebKit", "com.apple.Safari"] : families
        }
        let families = provider.activeBundleIdentifiers
        guard inputUsers.union(outputUsers).contains(where: { id in
            families.contains { id.matchesBundleFamily($0) }
        }) else { return nil }
        return families
    }

    static func read<Object>(objects: [Object]?, ownBundleID: String,
                             bundleID: (Object) -> String?,
                             input: (Object) -> Bool?, output: (Object) -> Bool?) -> Self {
        guard let objects else { return .unknown }
        var inputUsers: Set<String> = []
        var outputUsers: Set<String> = []
        var reliable = true
        for object in objects {
            guard let id = bundleID(object) else {
                reliable = false
                continue
            }
            guard !id.isEmpty, ownBundleID.isEmpty || !id.matchesBundleFamily(ownBundleID),
                  MeetingPromptProvider.micInputProvider(forBundleID: id) != nil else { continue }
            guard let usesInput = input(object), let usesOutput = output(object) else {
                reliable = false
                continue
            }
            if usesInput { inputUsers.insert(id) }
            if usesOutput { outputUsers.insert(id) }
        }
        return Self(inputUsers: inputUsers, outputUsers: outputUsers, isReliable: reliable)
    }

    static func cameraInUse(readings: [Bool?]?) -> Bool? {
        guard let readings else { return nil }
        if readings.contains(true) { return true }
        return readings.contains(nil) ? nil : false
    }

    func activity(in families: Set<String>, cameraInUse: Bool?) -> MeetingEndDetectionPolicy.Activity {
        guard isReliable else { return .unknown }
        if cameraInUse == true || inputUsers.union(outputUsers).contains(where: { id in
            families.contains { id.matchesBundleFamily($0) }
        }) { return .active }
        return cameraInUse == nil ? .unknown : .inactive
    }
}

struct MeetingCallEndTracking {
    let recordingIdentity: UUID
    let families: Set<String>
    var policy = MeetingEndDetectionPolicy()

    func canStop(currentIdentity: UUID?, warningIdentity: UUID?, activity: MeetingEndDetectionPolicy.Activity,
                 at now: TimeInterval) -> Bool {
        recordingIdentity == currentIdentity && recordingIdentity == warningIdentity
            && activity == .inactive && policy.canStop(at: now)
    }
}

/// Time is monotonic and supplied by the caller, so sleep, unknown reads and
/// missed polls cannot count as confirmed call inactivity.
struct MeetingEndDetectionPolicy {
    enum Activity { case active, inactive, unknown }
    enum Event: Equatable { case none, warningStarted, warningCleared, stop }

    let inactivityInterval: TimeInterval
    let countdownInterval: TimeInterval
    let maximumSampleGap: TimeInterval
    private var lastSampleAt: TimeInterval?
    private var inactiveSince: TimeInterval?
    private var deadline: TimeInterval?
    private var suppressed = false

    init(inactivityInterval: TimeInterval = 10, countdownInterval: TimeInterval = 30,
         maximumSampleGap: TimeInterval = 12) {
        self.inactivityInterval = inactivityInterval
        self.countdownInterval = countdownInterval
        self.maximumSampleGap = maximumSampleGap
    }

    mutating func observe(_ activity: Activity, at now: TimeInterval) -> Event {
        guard !suppressed else { return .none }
        let gap = lastSampleAt.map { now - $0 }
        lastSampleAt = now
        if let gap, gap < 0 || gap > maximumSampleGap {
            let event = clearWarning()
            // A new sample starts a fresh interval after a suspended monitor.
            inactiveSince = activity == .inactive ? now : nil
            return event
        }
        switch activity {
        case .active, .unknown:
            return clearWarning()
        case .inactive:
            if let deadline { return now >= deadline ? .stop : .none }
            guard let inactiveSince else {
                self.inactiveSince = now
                return .none
            }
            guard now - inactiveSince >= inactivityInterval else { return .none }
            deadline = now + countdownInterval
            return .warningStarted
        }
    }

    /// The UI countdown cannot stop a call on stale evidence between scans.
    func canStop(at now: TimeInterval) -> Bool {
        guard !suppressed, let deadline, let lastSampleAt else { return false }
        return now >= deadline && now >= lastSampleAt && now - lastSampleAt <= maximumSampleGap
    }

    mutating func keepRecording() {
        suppressed = true
        _ = clearWarning()
    }

    private mutating func clearWarning() -> Event {
        let hadWarning = deadline != nil
        deadline = nil
        inactiveSince = nil
        return hadWarning ? .warningCleared : .none
    }
}
