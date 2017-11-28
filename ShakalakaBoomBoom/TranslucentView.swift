//
//  TranslucentView.swift
//
//  Created by Arunkulkarni on 29/06/16.
//

import UIKit

enum BlurType: Int {
    case extraLightBlur
    case lightBlur
    case darkBlur
    case none
}

// Wrapper for creating a view with either blur, vibrance or color
class TranslucentView: UIView {
    // Letting the view have a defined frame
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: GeneralConstants.screenWidth, height: GeneralConstants.screenHeight))
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    /**
     Sets a desired Blur effect to the view along with desired Color with or without Vibrancy
     - parameter blurType: BlurType required, give none if no blur needed
     - parameter vibrancyRequired: YES if requird over the blur, NO if, only blur is required
     - parameter bgColor: The color along with desired alpha value
     - returns: the view with blur, vibrancy and color
     */
    func setTranslucentProperties(blurType: BlurType = .none, vibrancyRequired: Bool = false, bgColor: UIColor = UIColor.clear) {
        self.backgroundColor = bgColor
        
        if blurType != .none {
            if let blurStyle = UIBlurEffectStyle(rawValue: blurType.rawValue) {
                let blurEffect: UIBlurEffect = UIBlurEffect(style: blurStyle)
                let blurView = UIVisualEffectView(effect: blurEffect)
                blurView.frame = self.bounds
                self.addSubview(blurView)
                
                if vibrancyRequired {
                    let vibrancy = UIVibrancyEffect(blurEffect: blurView.effect as! UIBlurEffect)
                    let vibrancyView = UIVisualEffectView(effect: vibrancy)
                    vibrancyView.frame = blurView.bounds
                    blurView.contentView.addSubview(vibrancyView)
                }
            }
        }
    }
}
