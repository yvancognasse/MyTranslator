import Foundation

@main
struct StabilityTests {
    static func main() throws {
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
        print("PASS: large input/output, concurrent stderr, stalled stdin timeout, nonzero exit, broken pipe, selection identity guards")
    }
}
