import Foundation

// Refuse redirects: credentials must never travel to a redirected endpoint.
final class API: NSObject, URLSessionTaskDelegate {
    private var session: URLSession!
    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 3
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    @discardableResult
    func get<T: Decodable>(_ type: T.Type, connection: Connection, path: String, query: [URLQueryItem] = [], completion: @escaping (Result<T, Error>) -> Void) -> URLSessionDataTask {
        var components = URLComponents(url: connection.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer " + connection.key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<T, Error> = Result {
                if let error = error { throw error }
                guard let http = response as? HTTPURLResponse else { throw ServiceError.message("服务未返回有效响应。") }
                switch http.statusCode {
                case 200...299: break
                case 401: throw ServiceError.blocking("API Key 无效或已撤销，请更新连接设置。")
                case 403: throw ServiceError.message("API Key 没有访问权限。")
                case 404: throw ServiceError.message("找不到接口，请检查 API 地址与 Umami 版本。")
                case 429: throw ServiceError.blocking("请求已被限流，请稍后手动刷新。")
                case 300...399: throw ServiceError.message("服务发生重定向，请直接填写最终 API 地址。")
                default: throw ServiceError.message("服务请求失败（HTTP \(http.statusCode)）。")
                }
                do { return try JSONDecoder().decode(T.self, from: data ?? Data()) }
                catch { throw ServiceError.message("响应格式不兼容，请确认服务支持当前 Umami API。") }
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }
    struct Page: Decodable { let data: [Website]; let count: Int? }
    func websites(connection: Connection, completion: @escaping (Result<[Website], Error>) -> Void) {
        func page(_ number: Int, accumulated: [Website]) {
            get(Page.self, connection: connection, path: "websites", query: [URLQueryItem(name: "page", value: String(number)), URLQueryItem(name: "pageSize", value: "100")]) { result in
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let response):
                    let all = accumulated + response.data
                    if !response.data.isEmpty && all.count < (response.count ?? all.count) && number < 100 { page(number + 1, accumulated: all) }
                    else { completion(.success(all)) }
                }
            }
        }
        page(1, accumulated: [])
    }
}
