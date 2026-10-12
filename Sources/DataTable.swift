import AppKit

struct DataRow {
    let id:String
    let cells:[String:String]
    var checked:Bool? = nil
    var canToggle = false
}
final class DataTable:NSView,NSTableViewDataSource,NSTableViewDelegate {
    var rows:[DataRow] = []
    let table = NSTableView()
    var toggled:((String,Bool) -> Void)?
    init(columns:[(String,String,CGFloat)],height:CGFloat) {
        super.init(frame:.zero)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:leadingAnchor),scroll.trailingAnchor.constraint(equalTo:trailingAnchor),scroll.topAnchor.constraint(equalTo:topAnchor),scroll.bottomAnchor.constraint(equalTo:bottomAnchor),heightAnchor.constraint(equalToConstant:height)])
        table.headerView = NSTableHeaderView(); table.rowHeight = 34; table.usesAlternatingRowBackgroundColors = true; table.gridStyleMask = [.solidHorizontalGridLineMask]; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self
        for (key,title,width) in columns { let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(key)); column.title = title; column.width = width; column.minWidth = 45; table.addTableColumn(column) }
        scroll.documentView = table
    }
    required init?(coder:NSCoder) { fatalError() }
    func setRows(_ next:[DataRow]) { rows = next; table.reloadData() }
    func numberOfRows(in tableView:NSTableView) -> Int { rows.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        guard rows.indices.contains(row), let column = tableColumn else { return nil }; let entry = rows[row], key = column.identifier.rawValue
        if key == "enabled" {
            let button = NSButton(checkboxWithTitle:"",target:self,action:#selector(checkChanged(_:))); button.state = entry.checked == true ? .on:.off; button.isEnabled = entry.canToggle; button.identifier = NSUserInterfaceItemIdentifier(entry.id)
            button.setAccessibilityLabel(tr("启用 ","Enable ") + (entry.cells["model"] ?? entry.id)); return button
        }
        let field = NSTextField(labelWithString:entry.cells[key] ?? "—"); field.font = .systemFont(ofSize:12); field.lineBreakMode = .byTruncatingTail; field.toolTip = key == "source" ? entry.cells["sourceURL"] ?? field.stringValue:field.stringValue
        let cell = NSTableCellView(); cell.addSubview(field); field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:5),field.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-5),field.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
        cell.textField = field; return cell
    }
    @objc func checkChanged(_ button:NSButton) { guard let id = button.identifier?.rawValue else { return }; toggled?(id,button.state == .on) }
}
struct PriceListing {
    let key:String
    let name:String
    let client:String
    let price:APIPrice?
    let date:String
    func outputUSD(fx:Double) -> Double { guard let p = price else { return -1 }; return p.output / (p.currency == "CNY" ? fx:1) }
    func inputUSD(fx:Double) -> Double { guard let p = price else { return -1 }; return p.input / (p.currency == "CNY" ? fx:1) }
    func amount(input:Bool,currency:String,fx:Double) -> String {
        guard let p = price else { return tr("待核实","Unverified") }
        let value = (input ? p.input:p.output) * (p.currency == currency ? 1:(currency == "CNY" ? fx:1/fx))
        return (currency == "CNY" ? "¥":"$") + String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),value)
    }
}
extension PriceBook {
    func listing(book:RuleBook,market:MarketSnapshot?) -> [PriceListing] {
        var rows = book.models.values.map { model in PriceListing(key:model.key,name:model.name,client:model.client.name,price:models[model.key],date:models[model.key]?.updated ?? checked) }
        let known = Set(PublicCatalog.bindings.values)
        for item in market?.models ?? [] where !known.contains(item.key) {
            let p:APIPrice? = item.input.flatMap { input in item.output.map { APIPrice(currency:"USD",input:input,output:$0,source:item.source,note:"Models.dev community API reference",updated:market?.fetchedAt) } }
            rows.append(PriceListing(key:item.key,name:item.name,client:item.provider,price:p,date:p?.updated ?? item.updated))
        }
        return rows.sorted { a,b in
            let outA = a.outputUSD(fx:cnyPerUSD), outB = b.outputUSD(fx:cnyPerUSD)
            if outA != outB { return outA > outB }
            let inA = a.inputUSD(fx:cnyPerUSD), inB = b.inputUSD(fx:cnyPerUSD)
            return inA == inB ? a.key < b.key:inA > inB
        }
    }
}
