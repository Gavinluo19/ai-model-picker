import Foundation
import CoreFoundation

struct CatalogModel:Codable,Equatable {
    let provider:String
    let id:String
    let name:String
    let released:String
    let updated:String
    let input:Double?
    let output:Double?
    var key:String { provider + "/" + id }
    var source:String { "https://models.dev/" }
}
struct MarketSnapshot:Codable {
    let fetchedAt:String
    let models:[CatalogModel]
}
struct FXQuote:Codable,Equatable {
    let date:String
    let rate:Double
    let source:String
}
struct UpdateOutcome {
    var market:MarketSnapshot?
    var fx:FXQuote?
    var failures:[String] = []
}
enum PublicCatalog {
    static let providers:Set<String> = ["openai","anthropic","moonshotai-cn","zhipuai","deepseek"]
    // Explicit provider IDs, never fuzzy names. Retired aliases are not selected.
    static let bindings:[String:String] = ["sol61":"openai/gpt-6.1-sol","astra":"openai/gpt-6-astra","sonnet55":"anthropic/claude-sonnet-5-5","opus55":"anthropic/claude-opus-5-5","wb_k3":"moonshotai-cn/kimi-k3","trae_k3":"moonshotai-cn/kimi-k3","wb_glm53":"zhipuai/glm-5.3","trae_glm53":"zhipuai/glm-5.3","wb_glm53flash":"zhipuai/glm-5.3-flash","wb_ds41":"deepseek/deepseek-flash","trae_ds41":"deepseek/deepseek-flash"]
    static func number(_ raw:Any?) -> Double? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, (0...100000).contains(n.doubleValue) else { return nil }; return n.doubleValue
    }
    static func parse(_ data:Data,at:String) throws -> MarketSnapshot {
        guard data.count <= 12_000_000, let root = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw RouterError(tr("在线模型目录格式不正确。","The online catalog format is invalid.")) }
        var models:[CatalogModel] = []
        for provider in providers.sorted() {
            guard let source = root[provider] as? [String:Any], let values = source["models"] as? [String:Any], values.count <= 1000 else { continue }
            for (id,raw) in values {
                guard let m = raw as? [String:Any], let name = m["name"] as? String, !name.isEmpty, name.count <= 180, id.range(of:"^[a-zA-Z0-9_.:/-]{1,160}$",options:.regularExpression) != nil else { continue }
                let modalities = m["modalities"] as? [String:[String]] ?? [:]
                guard modalities["output"]?.contains("text") == true else { continue }
                if ["embedding","tts","transcribe","audio","realtime","moderation"].contains(where: { id.lowercased().contains($0) }) { continue }
                let cost = m["cost"] as? [String:Any] ?? [:]
                let input = number(cost["input"]), output = number(cost["output"])
                // Zero is not proof that a desktop subscription or model API is free.
                let known = input != nil && output != nil && (input! > 0 || output! > 0)
                models.append(CatalogModel(provider:provider,id:id,name:name,released:String((m["release_date"] as? String ?? "").prefix(10)),updated:String((m["last_updated"] as? String ?? "").prefix(10)),input:known ? input:nil,output:known ? output:nil))
            }
        }
        guard !models.isEmpty, models.count <= 1500 else { throw RouterError(tr("目录没有支持厂商的文字模型，保留原目录。","No supported text models were found. The previous catalog is retained.")) }
        models.sort { $0.released == $1.released ? $0.key < $1.key:$0.released > $1.released }
        return MarketSnapshot(fetchedAt:at,models:models)
    }
    static func parseFX(_ data:Data) throws -> FXQuote {
        guard data.count <= 32_768, let j = try JSONSerialization.jsonObject(with:data) as? [String:Any], j["base"] as? String == "USD", j["quote"] as? String == "CNY", let rate = number(j["rate"]), (0.1...100).contains(rate), let date = j["date"] as? String, date.range(of:"^20[0-9]{2}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil else { throw RouterError(tr("汇率响应不正确，保留原汇率。","The FX response is invalid. The previous rate is retained.")) }
        return FXQuote(date:date,rate:rate,source:"https://frankfurter.dev/")
    }
    static func merge(prices:PriceBook,market:MarketSnapshot?,fx:FXQuote?) -> PriceBook {
        var values = prices.models
        if let market = market {
            let exact = Dictionary(uniqueKeysWithValues:market.models.map { ($0.key,$0) })
            for (key,identity) in bindings {
                guard let item = exact[identity], let input = item.input, let output = item.output else { continue }
                values[key] = APIPrice(currency:"USD",input:input,output:output,source:item.source,note:"Models.dev community reference; provider normalized USD rates. Cache, context tiers and processing modes may differ.",updated:market.fetchedAt)
            }
        }
        return PriceBook(checked:prices.checked,cnyPerUSD:fx?.rate ?? prices.cnyPerUSD,exchangeNote:fx == nil ? prices.exchangeNote:"Frankfurter daily reference",models:values,fxDate:fx?.date ?? prices.fxDate,fxSource:fx?.source ?? prices.fxSource,fetchedAt:market?.fetchedAt ?? prices.fetchedAt)
    }
}
final class PublicUpdateClient {
    typealias Transport = (URLRequest) async throws -> (Data,HTTPURLResponse)
    let transport:Transport
    static let catalogURL = URL(string:"https://models.dev/api.json")!
    static let fxURL = URL(string:"https://api.frankfurter.dev/v2/rate/usd/cny")!
    init(transport:Transport? = nil) {
        if let transport = transport { self.transport = transport; return }
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 12; configuration.timeoutIntervalForResource = 20; configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        let session = URLSession(configuration:configuration,delegate:NoRedirects(),delegateQueue:nil)
        self.transport = { request in let (data,response) = try await session.data(for:request); guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }; return (data,response) }
    }
    private func get(_ url:URL) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url:url); request.httpMethod = "GET"; request.timeoutInterval = 12
        request.setValue("AIModelPicker/0.4",forHTTPHeaderField:"User-Agent"); request.setValue("application/json",forHTTPHeaderField:"Accept")
        let (data,response) = try await transport(request); try Task.checkCancellation()
        guard response.statusCode == 200, data.count <= 12_000_000 else { throw RouterError(tr("公开数据源暂不可用，保留原数据。","The public source is unavailable. Previous data is retained.")) }; return data
    }
    func fetch() async throws -> UpdateOutcome {
        let stamp = ISO8601DateFormatter().string(from:Date())
        async let models = Result(catching: { try await PublicCatalog.parse(self.get(Self.catalogURL),at:stamp) })
        async let fx = Result(catching: { try await PublicCatalog.parseFX(self.get(Self.fxURL)) })
        let (m,f) = await (models,fx); try Task.checkCancellation()
        var result = UpdateOutcome()
        switch m { case .success(let value): result.market = value; case .failure: result.failures.append(tr("模型/价格未更新","Models/prices unchanged")) }
        switch f { case .success(let value): result.fx = value; case .failure: result.failures.append(tr("汇率未更新","FX unchanged")) }
        return result
    }
}
// Async Result helper keeps failures independent without swallowing task cancellation.
private extension Result where Failure == Error {
    init(catching body:() async throws -> Success) async { do { self = .success(try await body()) } catch { self = .failure(error) } }
}

struct MarketCache:Codable { let market:MarketSnapshot?; let prices:PriceBook }
