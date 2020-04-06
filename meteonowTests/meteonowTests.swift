//
//  meteonowTests.swift
//  meteonowTests
//
//  Created by Nicolas Witczak on 31/05/2019.
//  Copyright © 2019 Nicolas Witczak. All rights reserved.
//

import XCTest
import MapKit
@testable import Promises
@testable import meteonow


extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

class LeakTest
{
    var buffer : [Int] = Array(1...1000000)
    var name : String
    
    init( _ aname : String)
    {
        name = aname
        //print("init \(name)")
    }
    
    deinit
    {
        //print("deinit \(name)")
    }
}

enum TestingError : Error
{
    case Test
}

class meteonowTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testMinToRad()
    {
        // given
        let cases : [ ( CGFloat , CGFloat ) ] = [ ( 0 , 3 * .pi / 2 ) , ( 15 , 0 ) , ( 30 , .pi / 2 ) ,  ( 45 , .pi ) ]
        
        // then
        cases.forEach
        {
            XCTAssertEqual( $1 , MeteoView.minuteToRadian($0) , accuracy : 0.000000001 )
        }
    }
    
    func genStaticMeteoSvc() -> MeteoSvc
    {
        return MeteoSvc( StaticGeoQueryProvider(delai:2) , StaticAreaCodeQueryProvider(delai:2) ,StaticForecastQueryProvider(delai:2) )
    }
    
    func genCachedMeteoSvc() -> MeteoSvc
    {
        let outerIP = OuterInternetProvider()
        return MeteoSvc(
            CachedMapKitGeoQueryProvider() ,
            CachedMeteoFranceAreaCodeQueryProvider( outerIP ),
            CachedMeteoFranceForecastQueryProvider( outerIP ) )
    }
    
    func testMeteoDataUninit()
    {
        // given
        let afcsvc = genStaticMeteoSvc()
        
        // when
        let afcdata = afcsvc.last
        
        // then
        XCTAssert( afcdata.fetchDisplay.contains("non disponible") )
    }
    
    func testMeteoDataFetch()
    {
        // given
        let afcsvc = genStaticMeteoSvc()
        
        // when
        afcsvc.updateLocation( CLLocationCoordinate2D( latitude: -0.1, longitude: 41) ).then
        {
            _ in
            afcsvc.updateAll();
        }.then
        {
            let afcdata = afcsvc.last
        // then
            XCTAssertEqual( "Courbevoie", afcdata.town )
            XCTAssert( afcdata.availableForecast )
        }
        XCTAssert( waitForPromises(timeout: 50 ) )
    }
    
    func testMeteoCacheDataFetch()
    {
        // given
        let afcsvc = genCachedMeteoSvc()
        // when
        afcsvc.updateLocation( CLLocationCoordinate2D( latitude: 48.889297 , longitude: 2.245848) )
        .then
        {
            let afcdata = afcsvc.last
            // then
            XCTAssertEqual( "Puteaux", afcdata.town )
            XCTAssert( afcdata.availableForecast )
        }
        XCTAssert( waitForPromises(timeout: 50 ) )
    }
    
    func testCache()
    {
        //given
        class StringProvider : QueryProvider<Int,String>
        {

            public override func query( _ anum : Int ) -> Promise< String >
            {
                let astr = String( anum )
                let aprom = Promise( astr )
                return aprom
            }
        }
        let acache = CacheQueryProvider( StringProvider() , { left , right in return left == right } )

        //when
        let val1 = acache.query( 1 )
        let _ = acache.query( 2 )
        let val1cached = acache.query( 1 )
        
        //then
        XCTAssert( waitForPromises(timeout: 50 ) )
        XCTAssertEqual( val1.value, val1cached.value )
    }
    
    func isValid( _ entries : [GuiPieEntry] ) -> Bool
    {
        if entries.count < 2 { return false }
        for idx in 0...(entries.count - 2 )
        {
            if entries[idx].toMin != entries[idx+1].fromMin
            {
                return false
            }
        }
        if entries.first!.fromMin != 0 { return false }
        if entries.last!.toMin != 60 { return false }
        return true
    }
    
    func makeVoidMeteoData() -> MeteoData
    {
        let afcdata = MeteoData()
        afcdata.forecasts = [ .no , .small , .middle , .strong , .no , .small , .middle , .strong , .no , .small , .middle , .unknown  ]
        afcdata.startDate = Date()
        afcdata.fetchDate = Date().addingTimeInterval( -300 )
        afcdata.coord = CLLocationCoordinate2D()
        afcdata.areacode = 0
        afcdata.postcode = 0
        afcdata.town = "Test"
        return afcdata
    }
    
    
    
    func testNullMeteoGuiPie()
    {
        // given
        let afcdata = MeteoData()
        
        // when
        let _ = afcdata.locationDisplay
        let _ = afcdata.fetchDisplay
        let pie = afcdata.getGuiPie( Date() )
        
        // then
        XCTAssert( isValid( pie ) )
        XCTAssertEqual( 2, pie.count )
    }
    
    func testMeteoGuiPie()
    {
        // given
        let afcdata = makeVoidMeteoData()
        
        // when
        let pie = afcdata.getGuiPie( afcdata.startDate! )
        
        // then
        XCTAssert( isValid( pie ) )
        XCTAssertEqual( 12, pie.count )
    }
   
    func testMeteoGuiPieWithOldData()
    {
        // given
        let afcdata = makeVoidMeteoData()
        
        // when
        let pie = afcdata.getGuiPie( afcdata.startDate!.addingTimeInterval(7200) )
        
        // then
        XCTAssert( isValid( pie ) )
        XCTAssertEqual( 2, pie.count )
    }
    
    func testMeteoAlert()
    {
        // given
        let afcdata = makeVoidMeteoData()
        
        // when
        let alert = afcdata.getAlert(reqLevel: RainIndex.middle )
        
        // then
        XCTAssertEqual( minOffset(from: Date(), to: alert.date ) , 10 , accuracy : 0.1 )
    }
    
    func testMeteoGuiPieWithOffset()
    {
        // given
        let afcdata = makeVoidMeteoData()
        
        // when
        let useDate = afcdata.startDate!.addingTimeInterval( 140 )
        let pie = afcdata.getGuiPie( useDate )
        
        // then
        XCTAssert( isValid( pie ) )
        XCTAssertEqual( 13 , pie.count )
    }
    
    //
    func testdataTaskOnGoodURL()
    {
        // given
        let ip = OuterInternetProvider()
        let url = URL( string : "https://jsonplaceholder.typicode.com/todos/1")
        
        // when
        ip.dataTaskGet(url).then
        {
            res in
            let str = String(decoding: res , as: UTF8.self)
            XCTAssert( str.starts(with: "{"))
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    func testdataTaskRest()
    {
        // given
        struct TypicodeData : Encodable , Decodable
        {
            var userId: Int
            var id: Int
            var title : String
            var completed : Bool
        }
        
        let ip = OuterInternetProvider()
        let url = URL( string : "https://jsonplaceholder.typicode.com/todos/1")
        
        // when
        ip.restGet( url ).then
        {
            (typicodeobj : TypicodeData) in
            XCTAssertEqual( "delectus aut autem" , typicodeobj.title )
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    func testPromiseMultipleThen()
    {
        // given
        var counter = 0
        let aprom = Promise(1).delay(1)
        aprom.then
        {
            _ in
            counter += 1
        }
        aprom.then
        {
            _ in
            counter += 1
        }
        XCTAssert( waitForPromises(timeout: 10 ) )
        XCTAssertEqual( 2 , counter )
    }
    
    func testdataTaskOnBadURL()
    {
        // given
        let ip = OuterInternetProvider()
        let url = URL( string : "https://jsonplaceholderbid.typicode.com/todos/1")
        
        // when
        ip.dataTaskGet(url).then
        {
            _ in
            XCTFail()
            }.catch
        {
            error in
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    func testDecodeMeteoLieu()
    {
        //given
        let input = """
            [ {
            "id" : "920260",
            "indicatifInseePP" : null,
            "onTheSnowSkiiId" : 0,
            "nomAffiche" : "Courbevoie (92400)",
            "type" : "VILLE_FRANCE",
            "slug" : "courbevoie",
            "codePostal" : "92400",
            "timezone" : "Europe/Paris",
            "altitude" : 46,
            "altitudeMin" : 0,
            "altitudeMax" : 0,
            "distance" : 0.0,
            "nbHabitants" : 87638,
            "lat" : 48.89705,
            "lon" : 2.251994,
            "directDisplay" : false,
            "refStationId" : null,
            "refStationName" : null,
            "nbView" : 0,
            "lastMareeDate" : null,
            "parent" : null,
            "positionAffichageCarteX" : 0,
            "positionAffichageCarteY" : 0,
            "value" : "Courbevoie (92400)",
            "pluieAvalaible" : true
            } ]
            """
        
        // when
        do
        {
            let res : [MeteoLieuEntry] = try DecodeJson( Data(input.utf8) )
        
            // then
            XCTAssertEqual( "Courbevoie (92400)" , res[0].nomAffiche )
        }
        catch let error
        {
            print("json error: \(error)")
            XCTFail()
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    func testDecodeMeteoPluie()
    {
        //given
        let input = """
            {
            "idLieu" : "920260",
            "echeance" : "201906121845",
            "lastUpdate" : "1830",
            "isAvailable" : true,
            "hasData" : true,
            "niveauPluieText" : [ "De18h45 à 19h45 : Pas de précipitations" ],
            "dataCadran" : [ {
            "niveauPluieText" : "Précipitations modérées",
            "niveauPluie" : 3,
            "color" : "009ee0"
            }, {
            "niveauPluieText" : "Précipitations modérées",
            "niveauPluie" : 3,
            "color" : "009ee0"
            }, {
            "niveauPluieText" : "Précipitations fortes",
            "niveauPluie" : 4,
            "color" : "006ab3"
            }, {
            "niveauPluieText" : "Précipitations modérées",
            "niveauPluie" : 3,
            "color" : "009ee0"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            }, {
            "niveauPluieText" : "Pas de précipitations",
            "niveauPluie" : 1,
            "color" : "ffffff"
            } ]
            }
            """
        
        // when
        do
        {
            let res : MeteoPluie = try DecodeJson( Data(input.utf8) )
            let meteoData = try MeteoFranceForecastQueryProvider.decode( res )
            
            // then
            XCTAssertEqual( "920260" , res.idLieu )
            XCTAssertEqual( 12 , res.dataCadran.count )
            XCTAssertNotNil( meteoData.startDate )
            XCTAssertNotNil( meteoData.fetchDate )
            XCTAssertEqual( 12 , meteoData.forecasts.count )
        }
        catch let error
        {
            print("json error: \(error)")
            XCTFail()
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    func testReverseGeoLoc()
    {
        // given
        let geoprov = MapKitGeoQueryProvider()
        
        // when
        geoprov.query( CLLocationCoordinate2D( latitude: 48.889297 , longitude: 2.245848 ) ).then
        {// then
            address in
            XCTAssertEqual( 92800 , address.postcode )
        }.catch
        {
            error in
            XCTFail()
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    func testCachedReverseGeoLoc()
    {
        // given
        let geoprov = CachedMapKitGeoQueryProvider()
        
        // when
        geoprov.query( CLLocationCoordinate2D( latitude: 48.889297 , longitude: 2.245848 ) ).then
        {// then
            address in
            XCTAssertEqual( 92800 , address.postcode )
        }
        .catch
        {
            error in
            XCTFail()
        }
        geoprov.query( CLLocationCoordinate2D( latitude: 48.8244195 , longitude: 2.3578503 ) ).then
        {// then
            address in
            XCTAssertEqual( 75013 , address.postcode )
        }
        .catch
        {
            error in
            XCTFail()
        }
        geoprov.query( CLLocationCoordinate2D( latitude: 48.889297 , longitude: 2.245848 ) ).then
            {// then
                address in
                XCTAssertEqual( 92800 , address.postcode )
            }
            .catch
            {
                error in
                XCTFail()
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    func testQueryAreaCode()
    {
        // given
        let mfprov = MeteoFranceAreaCodeQueryProvider( OuterInternetProvider() )
    
        // when
        mfprov.query(92400).then
        {// then
            areacode in
            XCTAssertEqual( 920260 , areacode )
        }.catch
        {
            error in
            XCTFail()
        }
        XCTAssert( waitForPromises(timeout: 100 ) )
    }
    
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
