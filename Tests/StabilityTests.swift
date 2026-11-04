import Foundation

@main
struct StabilityTests {
    static func main() throws {
        // Missing AX focus is allowed only for capture in the same app.
        precondition(TextReplacementSafety.sameDestination(sourcePID: 10, currentPID: 10,
            sourceHasElement: false, currentHasElement: false, sameElement: false, inserting: false))
        precondition(!TextReplacementSafety.sameDestination(sourcePID: 10, currentPID: 10,
            sourceHasElement: false, currentHasElement: false, sameElement: false, inserting: true))
        precondition(!TextReplacementSafety.sameDestination(sourcePID: 10, currentPID: 11,
            sourceHasElement: false, currentHasElement: false, sameElement: false, inserting: false))
        precondition(!TextReplacementSafety.sameDestination(sourcePID: nil, currentPID: nil,
            sourceHasElement: false, currentHasElement: false, sameElement: false, inserting: false))
        for inserting in [false, true] {
            precondition(TextReplacementSafety.sameDestination(sourcePID: 10, currentPID: 10,
                sourceHasElement: true, currentHasElement: true, sameElement: true, inserting: inserting))
            precondition(!TextReplacementSafety.sameDestination(sourcePID: 10, currentPID: 10,
                sourceHasElement: true, currentHasElement: true, sameElement: false, inserting: inserting))
            precondition(!TextReplacementSafety.sameDestination(sourcePID: 10, currentPID: 10,
                sourceHasElement: true, currentHasElement: false, sameElement: false, inserting: inserting))
            precondition(!TextReplacementSafety.sameDestination(sourcePID: 10, currentPID: 10,
                sourceHasElement: false, currentHasElement: true, sameElement: false, inserting: inserting))
        }
        let environment = ProcessInfo.processInfo.environment
        let payload = Data(repeating: 65, count: 1_048_576)
        let echo = try TranslationProcess.run(executable: URL(fileURLWithPath: "/bin/cat"),
            arguments: [], environment: environment, input: payload, timeout: 5)
        precondition(echo.status == 0 && echo.output == payload)
        let noisy = try TranslationProcess.run(executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", "import sys; sys.stderr.write('e'*262144); sys.stderr.flush(); sys.stdout.buffer.write(sys.stdin.buffer.read())"],
            environment: environment, input: payload, timeout: 10)
        precondition(noisy.output == payload && noisy.errors.count == 262144)
        let started = Date()
        do {
            _ = try TranslationProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"], environment: environment, input: payload, timeout: 0.15)
            preconditionFailure("A stalled stdin reader must time out")
        } catch TranslationProcess.Failure.timedOut {
            precondition(Date().timeIntervalSince(started) < 2)
        }
        let failed = try TranslationProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 7"], environment: environment, input: Data(), timeout: 2)
        precondition(failed.status == 7)
        do {
            _ = try TranslationProcess.run(executable: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: [], environment: environment, input: payload, timeout: 2)
            preconditionFailure("Closed stdin must fail without a SIGPIPE crash")
        } catch TranslationProcess.Failure.inputFailed { }
        func allowed(_ pid: Int32?, _ same: Bool, _ selection: String?) -> Bool {
            TextReplacementSafety.canReplace(sourcePID: 10, currentPID: pid, sameElement: same,
                original: "Selected text", selected: selection,
                originalRange: NSRange(location: 0, length: 13), currentRange: NSRange(location: 0, length: 13))
        }
        precondition(allowed(10, true, "Selected text"))
        precondition(!allowed(11, true, "Selected text"))
        precondition(!allowed(10, false, "Selected text"))
        precondition(!allowed(10, true, "Changed selection"))
        precondition(!allowed(10, true, nil))
        precondition(!allowed(nil, true, "Selected text"))
        precondition(!TextReplacementSafety.canReplace(sourcePID: 10, currentPID: 10, sameElement: true,
            original: "word", selected: "word", originalRange: NSRange(location: 0, length: 4),
            currentRange: NSRange(location: 20, length: 4)))
        precondition(!TextReplacementSafety.canReplace(sourcePID: 10, currentPID: 10, sameElement: true,
            original: "word", selected: "word", originalRange: nil, currentRange: nil))
        func fallback(_ selected: String?, _ copied: String?,
                      _ originalRange: NSRange? = nil, _ currentRange: NSRange? = nil,
                      pid: Int32 = 10, same: Bool = true) -> Bool {
            TextReplacementSafety.canReplace(sourcePID: 10, currentPID: pid, sameElement: same,
                original: "word", selected: selected, originalRange: originalRange,
                currentRange: currentRange, copiedSelection: copied)
        }
        precondition(fallback("word", "word")) // Editor without AX ranges.
        precondition(fallback(nil, "word")) // Editor with clipboard-only selection access.
        precondition(!fallback(nil, nil)) // Failed verification copy.
        precondition(!fallback(nil, "changed"))
        precondition(!fallback("changed", "word"))
        precondition(!fallback(nil, "word", pid: 11))
        precondition(!fallback(nil, "word", same: false))
        precondition(!fallback("word", "word", NSRange(location: 0, length: 4),
                               NSRange(location: 20, length: 4)))
        precondition(fallback(nil, "word", NSRange(location: 0, length: 4),
                              NSRange(location: 0, length: 4)))
        precondition(TextReplacementSafety.canReplace(sourcePID: 10, currentPID: 10,
            sameElement: true, original: "one\r\ntwo", selected: "one\ntwo",
            originalRange: nil, currentRange: nil, copiedSelection: "one\ntwo"))
        // Verify the exact replacement, including UTF-16 offsets used by Accessibility.
        precondition(TextReplacementSafety.confirmsReplacement(before: "Hello world!", after: "Hello monde!",
            range: NSRange(location: 6, length: 5), replacement: "monde"))
        precondition(TextReplacementSafety.confirmsReplacement(before: "😀 world", after: "😀 monde",
            range: NSRange(location: 3, length: 5), replacement: "monde"))
        precondition(!TextReplacementSafety.confirmsReplacement(before: "monde world", after: "monde world",
            range: NSRange(location: 6, length: 5), replacement: "monde")) // Existing translation is not success.
        precondition(!TextReplacementSafety.confirmsReplacement(before: "Hello world!", after: "monde Hello world!",
            range: NSRange(location: 6, length: 5), replacement: "monde")) // Inserted at wrong location.
        precondition(!TextReplacementSafety.confirmsReplacement(before: nil, after: "monde",
            range: nil, replacement: "monde")) // Missing metadata is not confirmation.
        precondition(!TextReplacementSafety.confirmsReplacement(before: "hello", after: "monde",
            range: NSRange(location: Int.max, length: 5), replacement: "monde"))
        precondition(!TextReplacementSafety.confirmsReplacement(before: "hello", after: "monde",
            range: NSRange(location: 0, length: Int.max), replacement: "monde"))
        precondition(TextReplacementSafety.sameText("a\r\nb", "a\nb"))
        precondition(!TextReplacementSafety.sameText(" word", "word"))
        print("PASS: large input/output, concurrent stderr, stalled stdin timeout, nonzero exit, broken pipe, selection identity guards, clipboard selection fallback, exact replacement confirmation, Unicode offsets")
    }
}
