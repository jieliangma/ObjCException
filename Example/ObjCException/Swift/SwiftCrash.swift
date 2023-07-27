//
//  SwiftCrash.swift
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

import ObjCException

@objc(OCESwiftCrash)
public class SwiftCrash: NSObject {
    @objc public static func crash() {
        doCrash()
    }
    
    public static func doCrash() {
//        oce_try_catch({
//            let nullable: String? = nil
//            let string: String
//            string = nullable!
//            print(string)
//        }, { error in
//            print(error)
//        })
        
        // x86_64 的模拟器通过，真机失败。
//        oce_try_catch({
//            let nullable: String? = nil
//            let string = nullable!
//            print(string)
//        }, { exception in
//            print(exception)
//        })
    }
}
