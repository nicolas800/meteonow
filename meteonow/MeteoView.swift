//
//  SSMeteoView.swift
//  meteonow
//
//  Created by Nicolas Witczak on 31/05/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//

import UIKit
import QuartzCore

@IBDesignable
public class ColorPreview: UILabel
{
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView()
    {
        self.layer.cornerRadius = 5
        self.layer.masksToBounds = true
        self.text = " "
    }
}

@IBDesignable
public class MeteoViewAnim: UIView , UIViewControllerPreviewingDelegate
{
    public func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let controller = storyboard.instantiateViewController(withIdentifier: "Legend")
        controller.preferredContentSize = CGSize(width: 200, height: 400 )
        return controller
    }
    
    public func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
    }
    
    var subview = MeteoView()
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func createSubView() -> MeteoView
    {
        let asubview = MeteoView(frame: self.frame)
        asubview.translatesAutoresizingMaskIntoConstraints = true
        asubview.frame = self.bounds
        asubview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return asubview
    }
    
    @objc func isTapped(recognizer: UITapGestureRecognizer)
    {
    }
    
    private func setupView()
    {
        self.isUserInteractionEnabled = true
        let gesture = UITapGestureRecognizer(target: self, action: #selector(MeteoViewAnim.isTapped(recognizer:)))
        self.addGestureRecognizer(gesture)
        subview = createSubView()
        addSubview( subview )
    }
    
    @IBInspectable var ringRatio: CGFloat = 2.5
        {
        didSet
        {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable var graduationGap: CGFloat = 1.05
        {
        didSet
        {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable var graduationSize: CGFloat = 1.05
        {
        didSet
        {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable var outerRatio: CGFloat = 0.72
        {
        didSet
        {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable var textRatio: CGFloat = 0.9
        {
        didSet
        {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable var fontSize: CGFloat = 13
        {
        didSet
        {
            setNeedsDisplay()
        }
    }
    
    func setRainMap( _ rainMap : [GuiPieEntry]  , _ bAnimate : Bool = false )
    {
        if bAnimate
        {
            let newSubview = createSubView()
            newSubview.rainMap = rainMap
            UIView.transition(from: subview , to: newSubview, duration: 1 , options: UIView.AnimationOptions.transitionCrossDissolve)
            {
                _ in
                self.subview = newSubview
            }
        }
        else
        {
            subview.rainMap = rainMap
        }
    
    }

    static func genIBGuiPie( _ forecasts : [RainIndex] ) -> [GuiPieEntry]
    {
        var ret : [GuiPieEntry] = []
        let pieLength = 60.0 / Double(forecasts.count)
        for idx in 0 ..< forecasts.count
        {
            ret.append( GuiPieEntry(
                rain: forecasts[idx] ,
                fromMin: Double(idx) * pieLength ,
                toMin: Double(idx+1) * pieLength
            ) )
        }
        return ret
    }
    
    public override func prepareForInterfaceBuilder()
    {
        setRainMap( MeteoViewAnim.genIBGuiPie([ .no , .small , .middle , .strong , .no , .small , .middle , .strong , .no , .small , .middle , .unknown  ] ) , false )
    }
}

@available(iOS 13.0, *)
@available(iOS 13.0, *)
@IBDesignable
class MeteoView: UIView
{
    let minTextDisplay : CGFloat = 300.0 ;
    static let minTextDisplay : CGFloat = 300.0 ;
    static let unknownRain: UIColor = UIColor.tertiaryLabel
    static let noRain: UIColor = UIColor.quaternarySystemFill
    static let smallRain: UIColor = MeteoView.initColor( 204 , 238 , 255 )
    static let middleRain: UIColor = MeteoView.initColor( 107, 208, 255 )
    static let strongRain: UIColor = MeteoView.initColor( 0 , 141 , 249 )
    
    static func maxInnerSquare( _ rect: CGRect ) -> CGRect
    {
        let width = min( rect.width , rect.height )
        let outRect = CGRect( x:rect.midX - width / 2 , y:rect.midY - width / 2 , width:width , height:width )
        return outRect
    }
    
    var parent : MeteoViewAnim
    {
        get
        {
            return self.superview as! MeteoViewAnim
        }
    }
    
    static func minuteToRadian( _ from : CGFloat  ) -> CGFloat
    {
        var rad = (from - 15 ) * 2 * .pi / 60
        if rad < 0
        {
            rad += 2 * .pi
        }
        else if rad >= 2 * .pi
        {
            rad -= 2 * .pi
        }
        return rad
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        setupView()
    }
    
    private func setupView()
    {
        self.backgroundColor = UIColor.clear
    }
    
    func getColorRain( index : RainIndex ) -> UIColor
    {
        switch index {
        case .unknown:
            return MeteoView.unknownRain
        case .no:
            return MeteoView.noRain
        case .small:
            return MeteoView.smallRain
        case .middle:
            return MeteoView.middleRain
        case .strong:
            return MeteoView.strongRain
        }
    }
    
    func drawPie( center: CGPoint , outerRadius: CGFloat , innerRadius: CGFloat ,  from : CGFloat , to : CGFloat , color : UIColor )
    {
        let fromRad = MeteoView.minuteToRadian( from )
        let toRad = MeteoView.minuteToRadian( to )
        let path = UIBezierPath(arcCenter: center ,
                    radius: outerRadius ,
                    startAngle: fromRad ,
                    endAngle: toRad ,
                    clockwise: true)
        path.addArc(withCenter: center ,
                    radius: innerRadius ,
                    startAngle: toRad ,
                    endAngle: fromRad ,
                    clockwise: false)
        path.close()
        color.setFill()
        path.fill()
    }
    
    override func draw(_ rect: CGRect)
    {
        guard rainMap.count > 1 else { return }
        let outer = MeteoView.maxInnerSquare( rect )
        let center = CGPoint(x: outer.midX , y: outer.midY )
        let outerRadius = outer.width / 2
        let innerRadius = outerRadius / parent.ringRatio
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: parent.fontSize),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.label
        ]
        for pieEntry in rainMap
        {
            drawPie(
                center : center ,
                outerRadius: outerRadius * parent.outerRatio ,
                innerRadius: innerRadius ,
                from : CGFloat( pieEntry.fromMin ),
                to: CGFloat( pieEntry.toMin ),
                color: getColorRain( index : pieEntry.rain ) );
        }
        for displayMin in (0 ..< 6).map( { $0 * 10 } )
        {
            let xOuterRad = outerRadius * cos( MeteoView.minuteToRadian( CGFloat( displayMin ) ) )
            let yOuterRad = outerRadius * sin( MeteoView.minuteToRadian( CGFloat( displayMin ) ) )
            let xGradRad = xOuterRad * parent.outerRatio * parent.graduationGap
            let yGradRad = yOuterRad * parent.outerRatio * parent.graduationGap
            
            if outer.width > minTextDisplay && outer.height > minTextDisplay
            {
                let textrect = CGRect
                    .init(x: center.x, y: center.y, width: 38, height: 20 )
                    .offsetBy(
                        dx: xOuterRad * parent.textRatio ,
                        dy: yOuterRad * parent.textRatio )
                    .offsetBy(dx: -20, dy: -8 )
                "\(displayMin) m".draw( in : textrect , withAttributes: attrs )
            }
            let gradStart = CGPoint( x : xGradRad + center.x , y : yGradRad + center.y )
            let gradEnd = CGPoint( x : xGradRad * parent.graduationSize + center.x , y : yGradRad * parent.graduationSize + center.y )
            let aPath = UIBezierPath()
            aPath.move(to: gradStart)
            aPath.addLine(to: gradEnd)
            aPath.close()
            UIColor.black.set()
            aPath.stroke()
        }
    }
    
    static func initColor( _ red: Int , _ green: Int , _ blue : Int) -> UIColor
    {
        return UIColor.init( red: CGFloat(red) / 255.0 , green: CGFloat(green) / 255.0 , blue: CGFloat(blue) / 255.0, alpha: 1)
    }
    
    var rainMap: [GuiPieEntry] = []
    {
        didSet
        {
            setNeedsDisplay()
        }
    }
    
    
}
