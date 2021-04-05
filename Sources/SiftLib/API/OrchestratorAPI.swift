import Foundation

public class OrchestratorAPI {

    public enum Status: String {
        case enabled
        case disabled
        case quarantine
    }

    private let endpoint: String
    private let token: String
    private let session = URLSession.shared
    private let testPlan: String
    
    private let path = "/v1/sift"
    private let pathRun = "/v1/sift/run"
    private let pathResult = "/v1/sift/result"

    public init(endpoint: String, token: String, testPlan: String) {
        self.endpoint = endpoint
        self.token = token
        self.testPlan = testPlan
    }

    public func get(status: Status, platform: String = "IOS") -> Config? {
        
        guard let url = URL(string: endpoint + path)?
            .appending("testplan", value: testPlan)?
            .appending("status", value: status.rawValue.uppercased())?
            .appending("platform", value: platform) else {
            Log.error("Can't resolve URL endpoint")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "token")

        let result = session.sendSynchronous(request: request)
        
        if result.error != nil {
            Log.error("\(result.error!)")
            return nil
        }
        
        guard let data = result.data else {
            Log.error("Data is nil")
            return nil
        }
        guard let response = result.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            Log.error("Server error!")
            return nil
        }

        guard let mime = result.response?.mimeType, mime == "application/json" else {
            Log.error("Wrong MIME type!")
            return nil
        }

        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.error("JSON parse error: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func post(tests: [String], platform: String = "IOS") -> Bool {
        guard let url = URL(string: endpoint + path)?
                .appending("platform", value: platform) else {
            Log.error("Can't resolve URL endpoint")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let json: [String : Any] = ["tests": tests]
        let jsonData = try! JSONSerialization.data(withJSONObject: json, options: [])
        request.httpBody = jsonData

        let result = session.sendSynchronous(request: request)

        if result.error != nil {
           Log.error("\(result.error!)")
           return false
        }

        guard let response = result.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
           Log.error("Server error!")
           return false
        }
        
        return true
    }
    
    public func postRun() -> OrchestratorTestRun? {
        guard let url = URL(string: endpoint + pathRun)?
                .appending("testplan", value: testPlan)?
                .appending("platform", value: "IOS")
        else {
            Log.error("Can't resolve URL endpoint")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let result = session.sendSynchronous(request: request)

        if result.error != nil {
           Log.error("\(result.error!)")
           return nil
        }
        
        //Response data with run ID
        guard let data = result.data else {
            Log.error("Data is nil")
            return nil
        }
        
        guard let response = result.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
           Log.error("Server error!")
           return nil
        }
        guard let mime = result.response?.mimeType, mime == "application/json" else {
            Log.error("Wrong MIME type!")
            return nil
        }

        do {
            return try JSONDecoder().decode(OrchestratorTestRun.self, from: data)
        } catch {
            Log.error("JSON parse error: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func postResults(testResults: OrchestratorTestResults) -> Bool {
        guard let url = URL(string: endpoint + pathResult)?
                .appending("platform", value: "IOS")?
                .appending("testplan", value: testPlan) else {
            Log.error("Can't resolve URL endpoint")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonEncoder = JSONEncoder()
        guard let jsonData = try? jsonEncoder.encode(testResults) else {
            Log.error("Failed to encode Test Results")
            return false
        }
        request.httpBody = jsonData

        let result = session.sendSynchronous(request: request)

        if result.error != nil {
           Log.error("\(result.error!)")
           return false
        }
        
        guard let response = result.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
           Log.error("Server error!")
           return false
        }
        
        return true
    }
    
    // single file upload
    public func postImage(runIndex: Int, testID: Int, fileName: String) -> Bool {
        let shell = Run()
        do {
            let response = try shell.run("curl -X POST \"\(endpoint + "/v1/sift/upload")" +
                "?platform=IOS" +
                "&testplan=\(testPlan)\"" +
                " -H \"accept: */*\"" +
                " -H \"token: \(token)\"" +
                " -H \"test-id: \(testID)\"" +
                " -H \"run-index: \(runIndex)\"" +
                " -H \"Content-Type: multipart/form-data\"" +
                " -H \"User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 11_0_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.192 Safari/537.36\"" +
                " -F \"file=@\(fileName.replacingOccurrences(of: "\'", with: ""));type=image/png\"").output
            print(response)
        } catch {
            Log.error("Can not post failure images to testRun")
            return false
        }
        return true
    }

    // multi-upload upload; curl TODO: check response output -i
    public func postImages(runIndex: Int, fileNames: [String]) -> Bool {
        let fileObjects = fileNames.map { "-F \"file=@\($0.replacingOccurrences(of: "'", with: ""))\"" }.joined(separator: " ")
        print(fileObjects)
        let shell = Run()
        do {
            try shell.run("curl -X POST \"\(endpoint + "/v1/sift/multi-upload")" +
                "?platform=IOS" +
                "&testplan=\(testPlan)\"" +
                " -H \"accept: */*\"" +
                " -H \"token: \(token)\"" +
                " -H \"run-index: \(runIndex)\"" +
                " -H \"Content-Type: multipart/form-data\"" +
                " -H \"User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 11_0_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.192 Safari/537.36\" " +
                " \(fileObjects)")
        } catch {
            Log.error("Can not post failure images to testRun")
            Log.message(verboseMsg: "\(error)")
            return false
        }
        return true
    }
}
