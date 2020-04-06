//
//  AboutViexwControllerViewController.swift
//  meteonow
//
//  Created by Nicolas Witczak on 06/07/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//

import UIKit

class AboutViewController: UIViewController {

    @IBOutlet weak var ctrlVersion: UILabel!
    @IBOutlet weak var ctrlDetail: UITextView!
    override func viewDidLoad() {
        super.viewDidLoad()
        ctrlDetail.text = localize("labeldetail")
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") else {return}
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") else {return}
        ctrlVersion.text = "\(version) (build \(build))"
    }

}
