import AppKit
import Foundation
let destination = URL(fileURLWithPath:CommandLine.arguments[1])
let iconset = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
func draw(size:Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform(); transform.scale(by:scale); transform.concat()
    let tile = NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:200,yRadius:200)
    NSColor(calibratedWhite:0.11,alpha:1).setFill(); tile.fill()
    let coin = NSBezierPath(ovalIn:NSRect(x:190,y:190,width:644,height:644))
    let gradient = NSGradient(colors:[NSColor(calibratedRed:0.98,green:0.82,blue:0.43,alpha:1),NSColor(calibratedRed:0.75,green:0.49,blue:0.16,alpha:1)])!
    gradient.draw(in:coin,angle:115)
    NSColor(calibratedRed:0.98,green:0.90,blue:0.69,alpha:1).setStroke()
    let inner = NSBezierPath(ovalIn:NSRect(x:218,y:218,width:588,height:588)); inner.lineWidth = 10; inner.stroke()
    NSColor(calibratedWhite:0.16,alpha:1).setStroke()
    let branch = NSBezierPath(); branch.lineWidth = 48; branch.lineCapStyle = .round; branch.lineJoinStyle = .round
    branch.move(to:NSPoint(x:512,y:332)); branch.line(to:NSPoint(x:512,y:452)); branch.curve(to:NSPoint(x:376,y:592),controlPoint1:NSPoint(x:512,y:560),controlPoint2:NSPoint(x:376,y:496)); branch.line(to:NSPoint(x:376,y:650)); branch.stroke()
    let right = NSBezierPath(); right.lineWidth = 48; right.lineCapStyle = .round
    right.move(to:NSPoint(x:512,y:452)); right.curve(to:NSPoint(x:648,y:592),controlPoint1:NSPoint(x:512,y:560),controlPoint2:NSPoint(x:648,y:496)); right.line(to:NSPoint(x:648,y:650)); right.stroke()
    NSColor(calibratedWhite:0.16,alpha:1).setFill()
    for point in [NSPoint(x:512,y:326),NSPoint(x:376,y:656),NSPoint(x:648,y:656)] { NSBezierPath(ovalIn:NSRect(x:point.x-44,y:point.y-44,width:88,height:88)).fill() }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
}
for (name,size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    try draw(size:size).write(to:iconset.appendingPathComponent(name+".png"))
}
try draw(size:512).write(to:destination.appendingPathComponent("AppIcon.png"))
