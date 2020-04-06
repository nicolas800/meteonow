//
//  meteoData.swift
//  meteonow
//
//  Created by Nicolas Witczak on 03/06/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//

import Foundation
import Promises
import MapKit
import SwiftDate

struct MeteoLieuEntry : Encodable , Decodable
{
    var id : String
    var nomAffiche : String
    var type : String
    var slug : String
    var codePostal : String
    var timezone : String
    var altitude : Double
    var distance : Double
    var lat : Double
    var lon : Double
    var value:String
    var pluieAvalaible : Bool
}

struct MeteoPluieCadranEntry : Encodable , Decodable
{
    var niveauPluieText : String
    var niveauPluie : Int
    var color : String
}

struct MeteoPluie : Encodable , Decodable
{
    var idLieu : String
    var echeance : String
    var lastUpdate : String
    var isAvailable : Bool
    var hasData : Bool
    var dataCadran : [ MeteoPluieCadranEntry ]
}

public enum RainIndex : Int , Comparable
{
    case unknown = 0
    case no
    case small
    case middle
    case strong
    
    public func toString() -> String
    {
        switch self {
        case RainIndex.small :
            return localize("low")
        case RainIndex.middle:
            return localize("middle")
        case RainIndex.strong:
            return localize("strong")
        default :
            return ""
        }
    }
    
    public static func < (a: RainIndex, b: RainIndex) -> Bool {
        return a.rawValue < b.rawValue
    }
}

public struct GuiPieEntry
{
    var rain : RainIndex
    var fromMin : Double
    var toMin : Double
    
    static func sat( _ minute : Double ) -> Double
    {
        return min( 60 , max( 0, minute ) )
    }
    
    init( rain:RainIndex , fromMin: Double, toMin : Double )
    {
        self.rain = rain
        self.fromMin = GuiPieEntry.sat( fromMin )
        self.toMin = GuiPieEntry.sat( toMin )
    }
    
    var isEmpty : Bool
    {
        get
        {
            return toMin - fromMin  <= 0
        }
    }
}

public struct MeteoAlert
{
    var forecast : RainIndex = RainIndex.unknown
    var date: Date = Date()
    
    public var minutes : Double
    {
        return minOffset( from : Date() , to : self.date )
    }
    
    public static func testValue() -> MeteoAlert
    {
        return MeteoAlert(forecast: RainIndex.middle, date: Date().addingTimeInterval(800))
    }
}

public class MeteoData
{
    var coord : CLLocationCoordinate2D?
    var town : String?
    var postcode : Int?
    var areacode : Int?
    var forecasts : [RainIndex]?
    var startDate : Date?
    var fetchDate : Date?
    
    init()
    {}
    
    init( _ ref: CLLocationCoordinate2D? )
    {
        self.coord = ref
    }
    
    init( _ ref: MeteoData)
    {
        self.coord = ref.coord
        self.town = ref.town
        self.postcode = ref.postcode
        self.areacode = ref.areacode
        self.forecasts = ref.forecasts
        self.startDate = ref.startDate
        self.fetchDate = Date()
    }
    
    var availableGeo : Bool
    {
        get { return coord != nil }
    }
    
    var availableLocation : Bool
    {
        get { return availableGeo && town != nil && postcode != nil }
    }
    
    var availableAreaCode : Bool
    {
        get { return availableLocation && areacode != nil }
    }
    
    var availableForecast : Bool
    {
        get { return availableAreaCode && fetchDate != nil && forecasts != nil && startDate != nil }
    }
    
    var locationDisplay : String
    {
        get { return availableLocation ? "\(town!) (\(FormatPostCode(postcode!)))" : "_ _" }
    }
    
    var fetchDisplay : String
    {
        get
        {
            if !availableForecast
            {
                return localize( "Unavailable forecast" )
            }
            let updatedMin = Int( minOffset( from: fetchDate!, to: Date() ) )
            if updatedMin > 30
            {
                return localize( "More than 30 m ago" )
            }
            else if updatedMin == 0
            {
                return localize( "Right now" )
            }
            else
            {
                return String( format:localize( "%@ m ago" ) , "\(updatedMin)" )
            }
        }
    }
    
    func reduceGeo( _ coord : CLLocationCoordinate2D ) -> MeteoData
    {
        let newData = MeteoData( self )
        newData.coord = coord
        newData.forecasts = nil
        newData.areacode = nil
        newData.postcode = nil
        newData.town = nil
        return newData
    }
    
    func reduceArea( _ geoProv : GeoQueryProvider ) -> Promise<MeteoData>
    {
        guard availableGeo else { return Promise( MeteoError.GeoCoord ) }
        return geoProv.query( coord! ).then
        {
            (geodata) in
            if self.postcode != geodata.postcode
            {
                let newData = MeteoData( self )
                newData.town = geodata.town
                newData.postcode = geodata.postcode
                newData.areacode = nil
                newData.forecasts = nil
                return Promise( newData )
            }
            else
            {
                return Promise(self)
            }
        }
    }
    
    func reduceAreaCode( _ areaCodeProv : AreaCodeQueryProvider ) -> Promise< MeteoData >
    {
        guard availableLocation else { return Promise( self ) }
        return areaCodeProv.query( postcode! ).then
        {
            (areacode) in
            let newData = MeteoData( self )
            newData.areacode = areacode
            return Promise( newData )
        }
    }
    
    func reduceForecast( _ forecastProv : ForecastQueryProvider ) -> Promise<MeteoData>
    {
        guard availableAreaCode else { return Promise( MeteoError.AreaCode ) }
        return forecastProv.query( self.areacode! ).then
        {
            ( forecast: ForecastData ) in
            if !self.availableForecast || ( forecast.fetchDate >= self.fetchDate! && forecast.startDate >= self.startDate!)
            {
                let newData = MeteoData( self )
                newData.forecasts = forecast.forecasts
                newData.fetchDate = forecast.fetchDate
                newData.startDate = forecast.startDate
                return Promise(newData)
            }
            else
            {
                return Promise(self)
            }
        }
    }
    
    func reduceLocation(_ coord : CLLocationCoordinate2D , _ geoProv : GeoQueryProvider )-> Promise<MeteoData>
    {
        return reduceGeo(coord).reduceArea(geoProv)
    }
    
    func reduceAll(_ coord : CLLocationCoordinate2D , _ geoProv : GeoQueryProvider , _ areaCodeProv : AreaCodeQueryProvider , _ forecastProv : ForecastQueryProvider )-> Promise<MeteoData>
    {
        return reduceGeo(coord).reduceArea(geoProv).then
        {
            mdata in
            return mdata.reduceAreaCode(areaCodeProv)
        }.then
        {
            mdata in
            return mdata.reduceForecast(forecastProv)
        }
    }
    
    func makeEmptyGuiPie() -> [GuiPieEntry]
    {
        var ret : [GuiPieEntry] = []
        ret.append( GuiPieEntry( rain: .unknown , fromMin : 0 , toMin : 30 ) )
        ret.append( GuiPieEntry( rain: .unknown , fromMin : 30 , toMin : 60 ) )
        return ret
    }
    
    func getGuiPie( _ dateref : Date ) -> [GuiPieEntry]
    {
        var ret : [GuiPieEntry] = []
        if self.availableForecast
        {
            let pieLength = 60.0 / Double(forecasts!.count)
            let offset = minOffset(from: dateref , to: startDate! )
            for idx in 0 ..< forecasts!.count
            {
                let pieEntry = GuiPieEntry(
                    rain: forecasts![idx] ,
                    fromMin: offset + ( Double(idx) * pieLength ) ,
                    toMin: offset + ( Double(idx+1) * pieLength )
                )
                if !pieEntry.isEmpty
                {
                    ret.append(pieEntry)
                }
            }
            if ret.count == 0
            {
                ret = makeEmptyGuiPie()
            }
            else
            {
                if ret.first!.fromMin > 0
                {
                    ret.insert( GuiPieEntry( rain : .unknown , fromMin: 0 , toMin: ret.first!.fromMin ) , at : 0 )
                }
                if ret.last!.toMin < 60
                {
                    ret.append( GuiPieEntry( rain : .unknown , fromMin: ret.last!.toMin , toMin: 60 ) )
                }
            }
        }
        else
        {
            ret = makeEmptyGuiPie()
        }
        return ret
    }
    
    func getAlert( reqLevel :  RainIndex) -> MeteoAlert
    {
        var retval : MeteoAlert = MeteoAlert()
        guard let aforecasts = forecasts , let astartDate = startDate  else { return retval }
        for idx in 0 ..< forecasts!.count
        {
            if aforecasts[idx] >= reqLevel
            {
                let pieLength = 60 / aforecasts.count
                retval.forecast = aforecasts[idx]
                retval.date = astartDate + (idx * pieLength ).minutes
                return retval
            }
        }
        return retval
    }
}

public class MeteoSvc
{
    let geoProv : GeoQueryProvider
    let areaCodeProv : AreaCodeQueryProvider
    let forecastProv : ForecastQueryProvider
    var last : MeteoData = MeteoData()
    
    init()
    {
        self.geoProv  = EmptyGeoQueryProvider()
        self.areaCodeProv = EmptyAreaCodeQueryProvider()
        self.forecastProv = EmptyForecastQueryProvider()
    }
    
    init( _ geoProv : GeoQueryProvider  , _ areaCodeProv : AreaCodeQueryProvider , _ forecastProv : ForecastQueryProvider )
    {
        self.forecastProv = forecastProv
        self.areaCodeProv = areaCodeProv
        self.geoProv = geoProv
    }
    
    func clear()
    {
        last = MeteoData( last.coord )
    }
    
    func updateLocation( _ coord : CLLocationCoordinate2D ) -> Promise<Void>
    {
        last.coord = coord
        return last.reduceLocation( coord, geoProv ).then
        {
            newval in
            self.last.postcode = newval.postcode
            self.last.town = newval.town
            return Promise(())
        }
    }
    
    func updateAll() -> Promise<Void>
    {
        if let acoord = last.coord
        {
            return last.reduceAll( acoord, geoProv , areaCodeProv , forecastProv ).then
            {
                newval in
                self.last = newval
            }
        }
        else
        {
            return Promise.init(MeteoError.Internal)
        }
    }
}
