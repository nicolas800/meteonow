//
//  AppDelegate.swift
//  meteonow
//
//  Created by Nicolas Witczak on 31/05/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//

import UIKit
import UserNotifications
import MapKit
import CoreData
import Promises
import SwiftDate
import os.log

let MeteoDataLocationChanged = "MeteoDataLocationChanged"
let MeteoDataForecastChanged = "MeteoDataForecastChanged"

class Settings
{
    var foregroundTimerInterval = 3 * 60.0
    var backgroundTimerInterval = 10 * 60.0
    var isAlertSelected = true
    var forecastAlertLevel = RainIndex.middle
    var minMinuteAlert = 5.0
    var throttleAlertMinute = 30.0
    
    public func reload() -> Settings
    {
        let userDefault = UserDefaults.standard
        let retval = Settings()
        retval.foregroundTimerInterval = userDefault.double(forKey: SettingsBundleKeyConstant.kRefreshForeground) * 60
        retval.backgroundTimerInterval = userDefault.double(forKey: SettingsBundleKeyConstant.kRefreshBackground) * 60
        retval.isAlertSelected = userDefault.bool(forKey: SettingsBundleKeyConstant.kDoAlert)
        retval.forecastAlertLevel = RainIndex( rawValue: userDefault.integer(forKey: SettingsBundleKeyConstant.kRainLevel))!
        retval.throttleAlertMinute = userDefault.double(forKey: SettingsBundleKeyConstant.kThrottleAlert)
        return retval
    }
    
    public static func initSettings()
    {
        let settingsUrl = Bundle.main.url(forResource: "Settings", withExtension: "bundle")!.appendingPathComponent("Root.plist")
        let settingsPlist = NSDictionary(contentsOf:settingsUrl)!
        let preferences = settingsPlist["PreferenceSpecifiers"] as! [NSDictionary]
            
        var defaultsToRegister = Dictionary<String, Any>()
            
        for preference in preferences
        {
            guard let key = preference["Key"] as? String else {
                NSLog("Key not fount")
                continue
            }
            defaultsToRegister[key] = preference["DefaultValue"]
        }
        UserDefaults.standard.register(defaults: defaultsToRegister)
    }
}

class SettingsBundleKeyConstant
{
    static let kRefreshForeground = "kRefreshForeground"
    static let kRefreshBackground = "kRefreshBackground"
    static let kDoAlert = "kDoAlert"
    static let kRainLevel = "kRainLevel"
    static let kThrottleAlert = "kThrottleAlert"
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate , CLLocationManagerDelegate , InternetProvider , URLSessionDownloadDelegate , URLSessionTaskDelegate , URLSessionDelegate
{
    var window: UIWindow?
    let locationManager = CLLocationManager()
    var refreshTimer : Timer?
    var settings = Settings()
    var lastBkReq : PromiseCB< Data >?
    var meteoSvc = MeteoSvc()
    let outerIP = OuterInternetProvider()
    var authAlert = false
    var lastAlert : Date?
    // background fetch
    static let bkgIdentifier = "fr.sigma-solutions.meteonow.bg"
    private var bkgUrlSession: URLSession?
    var bkgCompletionHandler: (() -> Void)?
    
    func application(_ application: UIApplication,willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?) -> Bool
    {
        os_log("UIApplication.willFinishLaunchingWithOptions")
        Settings.initSettings()
        settings = settings.reload()
        meteoSvc = MeteoSvc(
            CachedMapKitGeoQueryProvider() ,
            CachedMeteoFranceAreaCodeQueryProvider( self ),
            CachedMeteoFranceForecastQueryProvider( self ) )
            //StaticForecastQueryProvider(delai:1))
        return true
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        os_log("UIApplication.didFinishLaunchingWithOptions")
        startGpsTracking()
        startTimer()
        UIApplication.shared.setMinimumBackgroundFetchInterval( settings.backgroundTimerInterval )
        let configuration = URLSessionConfiguration.background(withIdentifier: AppDelegate.bkgIdentifier)
        bkgUrlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        if settings.isAlertSelected
        {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            {
                didAllow, error in
                self.authAlert = didAllow
            }
        }
        return true
    }
    
    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        os_log("UIApplication.performFetchWithCompletionHandler")
        self.meteoSvc.updateAll().then( on: DispatchQueue.main )
        {
            os_log("UIApplication.performFetchWithCompletionHandler done OK")
            completionHandler( .newData )
            NotificationCenter.default.post(name: Notification.Name( MeteoDataForecastChanged ) , object: nil )
            self.notifyForecast()
        }
        .catch
        {
            error in
            os_log("UIApplication.performFetchWithCompletionHandler done with error")
            completionHandler( .noData )
        }
    }
    
    var IsBkReqPending : Bool
    {
        get { return bkgCompletionHandler != nil }
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession)
    {
        DispatchQueue.main.async
        {
            self.bkgCompletionHandler?()
            self.bkgCompletionHandler = nil
        }
    }
    
    func notifyForecast()
    {
        guard lastAlert == nil || minOffset(from: lastAlert!, to: Date() ) > settings.throttleAlertMinute else { return }
        guard settings.isAlertSelected && authAlert else { return }
        let alert = meteoSvc.last.getAlert( reqLevel: settings.forecastAlertLevel )
        guard alert.forecast >= settings.forecastAlertLevel else { return }
        guard alert.minutes > self.settings.minMinuteAlert else { return }
        lastAlert = Date()
        doNotifyForecast(alert)
    }
    
    fileprivate func doNotifyForecast(_ alert: MeteoAlert) {
        let content = UNMutableNotificationContent()
        content.title = localize("Rain alert")
        let offsetMinutes = Int(alert.minutes.rounded())
        if offsetMinutes > 0
        {
            content.subtitle = String( format:localize("level %@ in %@ min" ) , "\(String(describing: alert.forecast.toString() ))" , "\(offsetMinutes)" )
        }
        else
        {
            content.subtitle = String( format:localize("level %@ now" ) , "\(String(describing: alert.forecast.toString()))" )
        }
        content.badge = nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "MeteoNowIOSNotification", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error = error
        {
            lastBkReq?.reject(error)
            lastBkReq = nil
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
    {
        do
        {
            let data = try Data(contentsOf: location)
            lastBkReq?.fullfill(data)
            lastBkReq = nil
        }
        catch
        {
            lastBkReq?.reject(error)
            lastBkReq = nil
        }
    }
        
    func startGpsTracking()
    {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func stopGpstracking()
    {
        locationManager.stopUpdatingLocation()
    }
    
    func startTimer()
    {
        if refreshTimer == nil
        {
            self.refreshTimer = meteonow.startTimer(
                timeInterval: settings.foregroundTimerInterval ,
                target: self,selector: #selector(updateTimer) )
        }
    }
    
    func stopTimer()
    {
        meteonow.stopTimer(refreshTimer)
        refreshTimer = nil
    }
    
    @objc func updateTimer()
    {
        let _ = updateAll()
    }
    
    func dataTask(_ urlreq: URLRequest) -> Promise<Data>
    {
        let state = UIApplication.shared.applicationState
        switch state
        {
        case .background :
        
            guard !IsBkReqPending else { return Promise(MeteoError.Internal) }
            guard bkgUrlSession != nil else { return Promise(MeteoError.Internal) }
            bkgUrlSession!.downloadTask(with: urlreq).resume()
            return Promise< Data >()
            {
                fulfill, reject in
                self.lastBkReq = PromiseCB( fullfill: fulfill, reject: reject )
            }.timeout(on: .main , 30 )
        case .active :
            return outerIP.dataTask( urlreq )
        default:
            return Promise(MeteoError.Internal)
        }
    }
    
    func updateAll( _ coord : CLLocationCoordinate2D ) -> Promise<Void>
    {
        return meteoSvc.updateLocation( coord ).then
        {
            self.notifyUpdateView()
            self.meteoSvc.updateAll().then
            {
                self.notifyUpdateView()
            }
        }
    }
    
    fileprivate func notifyUpdateView()
    {
        NotificationCenter.default.post(name: Notification.Name( MeteoDataLocationChanged ) , object: nil )
    }
    
    func updateAll() -> Promise<Void>
    {
        return meteoSvc.updateAll().then
        {
            self.notifyUpdateView()
        }
    }
    
    func locationManager( _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    {
        if let location = locations.first
        {
            let _ = updateAll(location.coordinate)
        }
    }
    
    func locationManager( _ manager: CLLocationManager, didFailWithError error: Error)
    {
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
        stopTimer()
        stopGpstracking()
    }

}

