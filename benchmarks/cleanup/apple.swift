import Foundation
import FoundationModels
@main struct Bench {
 static func main() async throws {
  let dir = CommandLine.arguments[1]
  guard SystemLanguageModel.default.isAvailable else { print("Apple model unavailable: \(SystemLanguageModel.default.availability)"); return }
  let cases = try JSONDecoder().decode([[String]].self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/cases.json")))
  let prompt = try String(contentsOfFile: dir + "/prompt.txt", encoding: .utf8)
  for round in 0..<2 {
   for c in cases {
    let start = Date()
    do {
     let session = LanguageModelSession(instructions: prompt)
     let response = try await session.respond(to: "<transcript>\(c[1])</transcript>", options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 300))
     let row: [String: Any] = ["model":"apple", "round":round, "id":c[0], "input":c[1], "expected":c[2], "output":response.content, "seconds":Date().timeIntervalSince(start)]
     print(String(data: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), encoding: .utf8)!)
    } catch { print("ERROR \(c[0]): \(error)") }
    fflush(stdout)
   }
  }
 }
}
