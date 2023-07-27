//
//  CppSwiftCrash.swift
//  ObjCException_Example
//
//  Created by 马杰亮 on 2024/3/12.
//  Copyright © 2024 JieLiang Ma. All rights reserved.
//

import UIKit

@objc(OCECppSwiftCrash)
public class CppSwiftCrash: NSObject {
    @objc public static func crash() {
        doCrash()
    }
    
    @objc public static func crashDeeper() {
        doCrashDeeper()
    }
    
    static func doCrash() {
        cpp_crash()
    }
    
    static func doCrashDeeper() {
        cpp_crash_deeper()
    }
}
