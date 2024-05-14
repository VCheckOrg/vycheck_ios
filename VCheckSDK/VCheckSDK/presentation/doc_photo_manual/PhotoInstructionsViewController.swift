//
//  PhotoInstructionsViewController.swift
//  VcheckSDKDemoIOS
//
//  Created by Kirill Kaun on 06.05.2022.
//

import Foundation
import UIKit

class PhotoInstructionsViewController : UIViewController {
    
    @IBOutlet weak var tvGoodCamera: PrimaryTextView!
    @IBOutlet weak var tvGoodLight: PrimaryTextView!
    
    @IBOutlet weak var proceedBtn: UIButton!
    
    @IBAction func backToDocType(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func proceedAction(_ sender: UIButton) {
        let data = VCheckSDKLocalDatasource.shared.getSelectedDocTypeWithData()
        if (data?.isSegmentationAvailable == true) {
            performSegue(withIdentifier: "PhotoInstructionsToSegStart", sender: nil)
        } else {
            performSegue(withIdentifier: "PhotoInstructionsToUpload", sender: nil)
        }
    }
    
    override func viewDidLoad() {
        self.proceedBtn.setTitle("proceed".localized, for: .normal)
        
        tvGoodCamera.text = "good_camera_text".localized;
        tvGoodLight.text = "good_doc_light_text".localized;
    }
}
