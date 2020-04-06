//
//  QueryProviders.swift
//  meteonow
//
//  Created by Nicolas Witczak on 17/06/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//

import Foundation
import Promises
import FBLPromises
import MapKit
import SwiftDate

public struct GeoData
{
    let town : String
    let postcode : Int
}

public class QueryProvider< IN : Equatable , OUT >
{
    public func query( _ in : IN ) -> Promise< OUT >
    {
        preconditionFailure("QueryProvider must be overridden")
    }
}

public func FormatPostCode( _ postcode : Int) -> String
{
    return String( String(postcode).paddingToLeft(upTo: 5,using:"0") )
}

public typealias GeoQueryProvider = QueryProvider< CLLocationCoordinate2D , GeoData >

public class ForecastData
{
    var forecasts : [RainIndex] = []
    var startDate : Date = Date()
    var fetchDate : Date = Date()
    
    init( forecasts : [RainIndex] , startDate : Date , fetchDate : Date )
    {
        self.forecasts = forecasts
        self.startDate = startDate
        self.fetchDate = fetchDate
    }
}

public typealias AreaCodeQueryProvider = QueryProvider< Int , Int >

public typealias ForecastQueryProvider = QueryProvider< Int , ForecastData>

public class CacheQueryProvider< IN : Equatable , OUT > : QueryProvider< IN , OUT >
{
    struct TEntry< IN , OUT >
    {
        var key : IN
        var value : Promise< OUT >
    }
    typealias Entry = TEntry< IN , OUT >
    typealias QP = QueryProvider< IN , OUT >
    var innerQp : QP
    var cache : Array< Entry > = Array()
    var comp : (IN ,IN) -> Bool
    
    init( _ innerQp : QP , _ comp : @escaping (IN ,IN) -> Bool )
    {
        self.innerQp = innerQp
        self.comp = comp
    }
    
    public override func query( _ ref : IN ) -> Promise<OUT>
    {
        var cached = cache.first
        {
            item in
            return comp( ref , item.key )
        }
        if cached == nil
        {
            let newPromise = innerQp.query(ref)
            cached = Entry( key: ref , value : newPromise )
            cache.append(cached!)
            newPromise.catch
            {
                _ in
                self.cache.removeAll
                {
                    elem in
                    return elem.key == ref
                }
            }
        }
        return cached!.value
    }
}

public class EmptyGeoQueryProvider : GeoQueryProvider
{
    public override func query( _ coord : CLLocationCoordinate2D ) -> Promise< GeoData >
    {
        return Promise( MeteoError.GeoLocation)
    }
}

public class StaticGeoQueryProvider : GeoQueryProvider
{
    let delai : TimeInterval
    
    init(delai:TimeInterval)
    {
        self.delai = delai
    }
    
    public override func query( _ coord : CLLocationCoordinate2D ) -> Promise< GeoData >
    {
        return Promise(GeoData( town : "Courbevoie", postcode : 92400 )).delay( self.delai  )
    }
}

public class MapKitGeoQueryProvider :  GeoQueryProvider
{
    public override func query( _ coord : CLLocationCoordinate2D ) -> Promise< GeoData >
    {
        let retval = Promise< GeoData >
        {
            fulfill, reject in
            CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            {
                places, error in
                guard places != nil && error == nil else{ reject(MeteoError.GeoLocation) ; return }
                guard let place = places!.first else { reject(MeteoError.GeoLocation) ; return }
                guard let postCodeString = place.postalCode else { reject(MeteoError.GeoLocation) ; return }
                guard let locality = place.locality else { reject(MeteoError.GeoLocation) ; return }
                guard let apostcode = try? toInt( postCodeString ) else { reject(MeteoError.GeoLocation) ; return }
                fulfill( GeoData( town : locality, postcode : apostcode ) )
            }
        }
        return retval
    }
}

public class CachedMapKitGeoQueryProvider : CacheQueryProvider< CLLocationCoordinate2D , GeoData >
{
    static let precision : Double = 0.002
    
    init()
    {
        super.init( MapKitGeoQueryProvider() ,
        {
            left , right in
            return abs(left.latitude - right.latitude) < CachedMapKitGeoQueryProvider.precision &&
                abs(left.longitude - right.longitude ) < CachedMapKitGeoQueryProvider.precision
        })
    }
}

public class EmptyAreaCodeQueryProvider : AreaCodeQueryProvider
{
    public override func query( _ postcode : Int ) -> Promise< Int >
    {
        return Promise( MeteoError.AreaCode)
    }
}

public class StaticAreaCodeQueryProvider : AreaCodeQueryProvider
{
    let delai : TimeInterval
    
    init(delai:TimeInterval)
    {
        self.delai = delai
    }
    
    public override func query( _ postcode : Int ) -> Promise< Int >
    {
        return Promise( 920260 ).delay( self.delai )
    }
}
public class EmptyForecastQueryProvider : ForecastQueryProvider
{
    public override func query( _ areacode : Int ) -> Promise< ForecastData >
    {
        return Promise( MeteoError.MeteoData)
    }
}

public class StaticForecastQueryProvider : ForecastQueryProvider
{
    let delai : TimeInterval
    
    init(delai:TimeInterval)
    {
        self.delai = delai
    }
    
    public override func query( _ areacode : Int ) -> Promise< ForecastData >
    {
        return Promise(
            ForecastData(
                // forecasts : [RainIndex](repeating: .unknown, count: 12 ) ,
                // forecasts : [ .no , .small , .middle , .strong , .no , .small , .middle , .strong , .no , .small , .middle , .strong  ],
                forecasts : [ .no , .no , .small , .middle , .no , .no , .strong , .strong , .small , .no , .small  , .no ],
                startDate : Date().addingTimeInterval( 300 )  ,
                fetchDate : Date() )
            ).delay( self.delai )
    }
}

public class MeteoFranceAreaCodeQueryProvider : AreaCodeQueryProvider
{
    let iprov : InternetProvider
    
    init( _ iprov:InternetProvider )
    {
        self.iprov = iprov
    }
    
    public override func query( _ postcode : Int ) -> Promise< Int >
    {
        let fmtPostCode = FormatPostCode(postcode)
        let anurl = URL( string : "http://www.meteofrance.com/mf3-rpc-portlet/rest/lieu/facet/pluie/search/\(fmtPostCode)" )
        return iprov.restGet( anurl )
        .then
        {
            ( res : [MeteoLieuEntry] ) -> Int in
            guard res.count > 0 else { throw MeteoError.AreaCode }
            return try toInt( res[0].id )
        }
    }
}

public class CachedMeteoFranceAreaCodeQueryProvider : CacheQueryProvider< Int,Int >
{
    init( _ iprov:InternetProvider )
    {
        super.init( MeteoFranceAreaCodeQueryProvider(iprov) ,
        {
            left , right in
            return left == right
        })
    }
}

public class MeteoFranceForecastQueryProvider : ForecastQueryProvider
{
    let iprov : InternetProvider
    
    init( _ iprov:InternetProvider )
    {
        self.iprov = iprov
    }
    
    static func decode( _ res : MeteoPluie) throws -> ForecastData
    {
        guard res.isAvailable else { throw MeteoError.MeteoData }
        let retval = ForecastData(
            forecasts : try res.dataCadran.map
            {
                entry in
                guard let lres = RainIndex( rawValue: entry.niveauPluie ) else { throw MeteoError.AreaCode }
                return lres
            },
            startDate : try parseDate( date : res.echeance , format : "yyyyMMddHHmm" ),
            fetchDate : Date()
        )
        return retval
    }
    
    public override func query( _ areacode : Int ) -> Promise< ForecastData >
    {
        let anurl = URL( string : "http://www.meteofrance.com/mf3-rpc-portlet/rest/pluie/\(areacode)" )
        return iprov.restGet( anurl )
        .then
        {
            ( res : MeteoPluie ) throws -> ForecastData in
            return try MeteoFranceForecastQueryProvider.decode( res )
        }
    }
}

public class CachedMeteoFranceForecastQueryProvider : ForecastQueryProvider
{
    let inner : ForecastQueryProvider
    var lastRes : Promise< ForecastData >?
    var isPending = false
    
    init( _ iprov:InternetProvider )
    {
        inner = MeteoFranceForecastQueryProvider(iprov)
    }
    
    public override func query( _ areacode : Int ) -> Promise< ForecastData >
    {
        if lastRes == nil || !isPending
        {
            lastRes = inner.query(areacode)
            self.isPending = true
            lastRes!.always
            {
                self.isPending = false
            }
        }
        return lastRes!
    }
}

public class ThrottleMeteoFranceForecastQueryProvider : ForecastQueryProvider
{
    let inner : ForecastQueryProvider
    let throttleMinutes : Double
    
    var lastRes : ForecastData?
    
    init( _ iprov : ForecastQueryProvider , _ throttleSecond : Double )
    {
        inner = iprov
        self.throttleMinutes = throttleSecond / 60
    }
    
    public override func query( _ areacode : Int ) -> Promise< ForecastData >
    {
        let decorateQuery =
        {
            (aquery : Promise< ForecastData >) -> Promise< ForecastData > in
            aquery.then
            {
                res in
                self.lastRes = res
            }
            return aquery
        }
        guard let aLastRes = lastRes
        else
        {
            return decorateQuery( inner.query(areacode) )
        }
        if minOffset( from: aLastRes.fetchDate , to : Date() ) >= throttleMinutes
        {
            return decorateQuery( inner.query(areacode) )
        }
        else
        {
            return Promise(aLastRes)
        }
    }
}
