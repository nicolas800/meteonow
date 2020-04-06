//
//  Helpers.swift
//  meteonow
//
//  Created by Nicolas Witczak on 10/06/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//
import Swift
import Foundation
import Promises
import MapKit

public func localize( _ astr : String ) -> String
{
    return NSLocalizedString(astr , comment:"")
}

public func ==(lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool
{
    return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
}

extension RangeReplaceableCollection where Self: StringProtocol
{
    func paddingToLeft(upTo length: Int, using element: Element = " ") -> SubSequence {
        return repeatElement(element, count: Swift.max(0, length-count)) + suffix(Swift.max(count, count-length))
    }
}

public enum MeteoError : Error
{
    case Internal
    case GeoCoord
    case GeoLocation
    case AreaCode
    case MeteoData
}

public func toInt( _ inStr : String ) throws -> Int
{
    guard let retval = Int( inStr , radix : 10 ) else { throw MeteoError.Internal }
    return retval
}

func parseDate( date : String , format : String ) throws -> Date
{
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = format
    guard let dateRet = dateFormatter.date( from : date ) else { throw MeteoError.MeteoData }
    return dateRet
}

public func minOffset(from : Date , to : Date) -> Double
{
    return Double(NSCalendar.current.dateComponents( [.second ], from: from, to: to ).second!) / 60.0
}

public struct PromiseCB<T>
{
    var fullfill : ((_ resolution: T ) -> Void)
    var reject : ((_ error: Error) -> Void)
}

public func DecodeJson<T>( _ buffer : Data ) throws -> T where T : Codable
{
    let jsonDecoder = JSONDecoder()
    let retval = try jsonDecoder.decode(T.self, from: buffer )
    return retval
}

public func startTimer( timeInterval ti: TimeInterval, target aTarget: Any, selector aSelector: Selector) -> Timer
{
    let aTimer = Timer.scheduledTimer(
        timeInterval: ti ,
        target: aTarget,
        selector: aSelector,
        userInfo: nil,
        repeats: true
    )
    aTimer.tolerance = ti / 10
    return aTimer
}

public func stopTimer( _ aTimer : Timer?)
{
    aTimer?.invalidate()
}

public func dataTaskHelper( _ urlreq: URLRequest ) -> Promise< Data >
{
    return Promise< Data >(/*on: .main*/)
    {
        fulfill, reject in
        URLSession.shared.dataTask(with: urlreq )
        {
            data, response, error -> Void in
            if error == nil
            {
                fulfill( data! )
            }
            else
            {
                reject( error! )
            }
        }.resume()
    }
}

protocol InternetProvider
{
    func dataTask( _ urlreq: URLRequest ) -> Promise< Data >
}

extension InternetProvider
{
    func dataTaskGet( _ url: URL? ) -> Promise< Data >
    {
        guard let anurl = url else { return Promise(MeteoError.Internal) }
        var request = URLRequest(
            url: anurl ,
            cachePolicy: NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData ,
            timeoutInterval: 10 )
        request.httpMethod = "GET"
        return dataTask(request)
    }
    
    func restGet<T>( _ url : URL? ) -> Promise<T> where T : Codable
    {
        return dataTaskGet(url).then
        {
            arg -> T in
            return try DecodeJson( arg )
        }
    }
}

public class OuterInternetProvider : InternetProvider
{
    func dataTask( _ urlreq: URLRequest ) -> Promise< Data >
    {
        return dataTaskHelper(urlreq)
    }
}




