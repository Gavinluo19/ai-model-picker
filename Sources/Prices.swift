import Foundation

struct APIPrice: Codable {
    let currency:String
    let input:Double
    let output:Double
    let source:String
    let note:String
    var updated:String? = nil
}
struct PriceBook: Codable {
    let checked:String
    let cnyPerUSD:Double
    let exchangeNote:String
    let models:[String:APIPrice]
    var fxDate:String? = nil
    var fxSource:String? = nil
    var fetchedAt:String? = nil
    static func load(_ url:URL?) -> PriceBook {
        guard let url = url, let book = try? read(url) else {
            return PriceBook(checked:"",cnyPerUSD:7,exchangeNote:"planning assumption",models:[:])
        }
        return book
    }
    func price(for model:ModelSpec) -> APIPrice? { models[model.key] }
    func summary(for model:ModelSpec) -> String {
        guard let price = price(for:model), ["USD","CNY"].contains(price.currency), price.input.isFinite, price.output.isFinite, price.input >= 0, price.output >= 0 else { return tr("API 参考价：待核实","API reference: unverified") }
        let wantsCNY = UIStrings.language == .zh
        let multiplier = wantsCNY ? (price.currency == "CNY" ? 1:cnyPerUSD) : (price.currency == "USD" ? 1:1/cnyPerUSD)
        let symbol = wantsCNY ? "¥":"$"
        func amount(_ n:Double) -> String { String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),n * multiplier) }
        return tr("输入 ","In ") + symbol + amount(price.input) + "  ·  " + tr("输出 ","Out ") + symbol + amount(price.output)
    }
    var disclaimer:String { tr("API 参考价 / 百万 Token · 非订阅扣费 · 参考汇率 $1≈¥\(String(format:"%.2f",cnyPerUSD))", "API reference / 1M tokens · Not subscription charges · FX $1≈¥\(String(format:"%.2f",cnyPerUSD))") }
}

extension PriceBook {
    static func read(_ url:URL) throws -> PriceBook {
        let data = try Data(contentsOf:url)
        guard data.count <= 65_536 else { throw RouterError(tr("价格表超过 64 KB。","Price reference exceeds 64 KB.")) }
        let book = try JSONDecoder().decode(PriceBook.self,from:data)
        guard (0.1...100).contains(book.cnyPerUSD), !book.models.isEmpty, book.models.count <= 100, book.checked.range(of:"^20[0-9]{2}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil,
            book.models.allSatisfy({ key,p in key.range(of:"^[a-zA-Z0-9_\\-]{1,64}$",options:.regularExpression) != nil && ["USD","CNY"].contains(p.currency) && p.input.isFinite && p.output.isFinite && (0...100000).contains(p.input) && (0...100000).contains(p.output) && URL(string:p.source)?.scheme == "https" && p.source.count <= 1000 && p.note.count <= 1000 }) else { throw RouterError(tr("价格表中的日期、币种、汇率或单价不合法。","The price date, currency, FX or rate is invalid.")) }
        return book
    }
}
