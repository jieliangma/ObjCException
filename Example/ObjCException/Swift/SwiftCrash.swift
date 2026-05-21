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

    /// Force-unwrap nil triggers Swift runtime → abort() → SIGABRT.
    /// `OCEException.catching` uses siglongjmp internally so the escape
    /// works regardless of the Swift runtime frames between the crash
    /// site and the catch site.
    public static func doCrash() {
        let exception = OCEException.catching {
            let nullable: String? = nil
            let s = nullable!
            print(s)
        }
        if let exception = exception {
            print("Swift caught: \(exception.name.rawValue) — \(exception.reason ?? "")")
        }
    }
}
