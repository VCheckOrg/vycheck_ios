//
//  ProviderModels.swift
//  VCheckSDK
//
//  Created by Kirill Kaun on 10.04.2023.
//

import Foundation

struct ProvidersResponse: Codable {

  var data      : [Provider]? = []
  var errorCode : Int?    = nil
  var message   : String? = nil

  enum CodingKeys: String, CodingKey {

    case data      = "data"
    case errorCode = "error_code"
    case message   = "message"
  
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)

    data      = try values.decodeIfPresent([Provider].self , forKey: .data      )
    errorCode = try values.decodeIfPresent(Int.self    , forKey: .errorCode )
    message   = try values.decodeIfPresent(String.self , forKey: .message   )
 
  }

  init() {
  }

}


struct Provider: Codable {

    var id      : Int
    var name : String
    var pRotocol: String
    var countries: [String]? = []

  enum CodingKeys: String, CodingKey {

    case id = "id"
    case name = "name"
    case pRotocol = "protocol"
    case countries = "countries"
  
  }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)

      self.id      = try values.decodeIfPresent(Int.self , forKey: .id      )!
      self.name = try values.decodeIfPresent(String.self   , forKey: .name ) ?? ""
      self.pRotocol = try values.decodeIfPresent(String.self   , forKey: .pRotocol )!
      self.countries = try values.decodeIfPresent([String].self , forKey: .countries ) ?? []
 
    }
    
    init(id: Int, name : String, pRotocol: String, countries: [String]? = []) {
        self.id = id
        self.name = name
        self.pRotocol = pRotocol
        self.countries = countries
    }
}


struct InitProviderRequestBody: Codable {
    
    var providerId: Int? = nil
    var country: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case providerId  = "provider_id"
        case country = "country"
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        providerId = try values.decodeIfPresent(Int.self , forKey: .providerId ) ?? -1
        country = try values.decodeIfPresent(String.self, forKey: .country) ?? nil
    }
    
    init(providerId: Int, country: String?) {
        self.providerId = providerId
        if (country != nil) {
            self.country = country
        }
    }
    
    init() {}
}


struct PriorityCountries: Codable {

  var data      : [String]? = []
  var errorCode : Int?    = nil
  var message   : String? = nil

  enum CodingKeys: String, CodingKey {

    case data      = "data"
    case errorCode = "error_code"
    case message   = "message"
  
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)

    data      = try values.decodeIfPresent([String].self , forKey: .data      )
    errorCode = try values.decodeIfPresent(Int.self    , forKey: .errorCode )
    message   = try values.decodeIfPresent(String.self , forKey: .message   )
 
  }

  init() {
  }

}
