import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = NSRect(x: CGFloat(pixels)*0.055, y: CGFloat(pixels)*0.055, width: CGFloat(pixels)*0.89, height: CGFloat(pixels)*0.89)
        let shape = NSBezierPath(roundedRect: rect, xRadius: CGFloat(pixels)*0.21, yRadius: CGFloat(pixels)*0.21)
        NSGradient(starting: NSColor(srgbRed:0.26,green:0.65,blue:1,alpha:1), ending: NSColor(srgbRed:0.10,green:0.35,blue:0.82,alpha:1))!.draw(in: shape, angle: -60)
        NSColor.white.setFill()
        for (i, h) in [0.17,0.32,0.49,0.32,0.17].enumerated() {
            let width = CGFloat(pixels)*0.065, height = CGFloat(pixels)*h
            NSBezierPath(roundedRect:NSRect(x:CGFloat(pixels)*(0.28+Double(i)*0.095),y:(CGFloat(pixels)-height)/2,width:width,height:height), xRadius:width/2,yRadius:width/2).fill()
        }
        image.unlockFocus()
        let data = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
        try data.write(to: URL(fileURLWithPath:output).appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
