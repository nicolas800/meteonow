//
//  ViewController.swift
//  meteonow
//
//  Created by Nicolas Witczak on 31/05/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//

import UIKit

class ViewController: UIViewController
{    
    @IBOutlet weak var meteoCtrl: MeteoViewAnim!
    @IBOutlet weak var locationCtrl: UILabel!
    @IBOutlet weak var updateTimeCtrl: UILabel!
    var refreshTimer : Timer?
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    static let refreshTimerInterval = 8.0
    var previousFetch : Date = Date()

    var app : AppDelegate
    {
        get
        {
            return (UIApplication.shared.delegate as! AppDelegate)
        }
    }
    
    var meteoSvc : MeteoSvc
    {
        get
        {
            return app.meteoSvc
        }
    }
    
    @objc func updateTimer()
    {
        self.refreshAll()
    }
    
    func refreshAll()
    {
        let last = self.meteoSvc.last
        self.locationCtrl.text = last.locationDisplay
        self.updateTimeCtrl.text = last.fetchDisplay
        var needAnimate : Bool = false
        if let lastFetch = last.fetchDate
        {
            needAnimate = previousFetch < lastFetch && last.availableForecast
            previousFetch = lastFetch
        }
        self.meteoCtrl.setRainMap( last.getGuiPie(Date()) , needAnimate )
        self.meteoCtrl.setNeedsDisplay()
    }
    
    @IBAction func onSettings(_ sender: Any)
    {
        if let url = URL.init(string: UIApplication.openSettingsURLString)
        {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    @objc func onMeteoDataForecastChanged(_ notification:Notification)
    {
        refreshAll()
    }
    
    @objc func onMeteoDataLocationChanged(_ notification:Notification)
    {
        refreshAll()
    }
    
    override func viewDidLoad()
    {
        self.activityIndicator.isHidden = true
        self.activityIndicator.hidesWhenStopped = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(onMeteoDataLocationChanged(_:)),
            name:  Notification.Name( MeteoDataLocationChanged ) ,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(onMeteoDataForecastChanged(_:)),
            name:  Notification.Name( MeteoDataForecastChanged ) ,
            object: nil)
        if refreshTimer == nil
        {
            refreshTimer = startTimer(
                timeInterval: ViewController.refreshTimerInterval ,
                target: self,selector: #selector(updateTimer))
        }
        registerForPreviewing( with: self.meteoCtrl , sourceView: self.meteoCtrl )
    }
    
    @IBAction func onRefreshForecast(_ sender: Any)
    {
        meteoSvc.clear()
        self.activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        app.updateAll().timeout(30).always( on:.main )
        {
            self.activityIndicator.stopAnimating()
        }
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        refreshAll()
    }
    
    override func viewDidDisappear(_ animated: Bool)
    {
        stopTimer( refreshTimer )
        refreshTimer = nil
    }
}

