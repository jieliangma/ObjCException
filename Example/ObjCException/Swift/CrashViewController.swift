//
//  CrashViewController.swift
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/11.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

import UIKit
import ObjCException

@objc(SwiftCrashType)
public enum CrashType: UInt {
    case swift, oc2Swift, cpp2Swift, swift2OC2Swift
}

@objc(SwiftCrashViewController)
public class CrashViewController: UIViewController {

    let crashType: CrashType
    
    @objc public init(crashType: CrashType) {
        self.crashType = crashType
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Swift crash"
        self.view.backgroundColor = UIColor.white
        
        let button = UIButton(frame: CGRectMake(100, 200, 100, 50))
        button.setTitle("Crash", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.setTitleColor(.gray, for: .highlighted)
        self.view.addSubview(button)
        button.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
    }
    
    @objc func buttonAction() {
        switch self.crashType {
        case .swift:
            SwiftCrash.doCrash()
        case .oc2Swift:
            OCECCallSwift.crash()
        case .cpp2Swift:
            OCECppCallSwift.crash()
        case .swift2OC2Swift:
            OCECCallSwift.crash()
        }
    }
}
