//
//  VCheckSDKConfig.swift
//  VcheckFramework
//

import Foundation

public struct VCheckURLConfig {
    let verificationApiBaseUrl: URL
    let verificationServiceUrl: String
    
    public init(verificationApiBaseUrl: URL, verificationServiceUrl: String) {
        self.verificationApiBaseUrl = verificationApiBaseUrl
        self.verificationServiceUrl = verificationServiceUrl
    }
    
    static func getDefaultConfig(for environment: VCheckEnvironment) -> VCheckURLConfig {
        switch environment {
        case .DEV:
            return VCheckURLConfig(
                verificationApiBaseUrl: URL(string: "https://test-verification.vycheck.com/api/v1/")!,
                verificationServiceUrl: "https://test-verification.vycheck.com"
            )
        case .PARTNER:
            return VCheckURLConfig(
                verificationApiBaseUrl: URL(string: "https://verification.vycheck.com/api/v1/")!,
                verificationServiceUrl: "https://verification.vycheck.com"
            )
        }
    }
}