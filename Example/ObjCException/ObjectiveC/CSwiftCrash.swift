//
//  CSwiftCrash.swift
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

import UIKit

@objc(OCECSwiftCrash)
public class CSwiftCrash: NSObject {
    @objc public static func crash(immediately: Bool) {
        if immediately {
            OCECCrash.crash()
        } else {
            crash()
        }
    }
    
    static func crash() {
        OCECCrash.crash()
    }
}
