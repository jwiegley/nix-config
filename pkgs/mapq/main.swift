import Foundation
import MapKit

// MARK: - JSON Output Structures

struct Origin: Encodable {
    let latitude: Double
    let longitude: Double
}

struct PlaceResult: Encodable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let straight_line_miles: Double
    let route_miles: Double
    let travel_minutes: Int
    let phone: String?
    let url: String?
    let text_summary: String
}

struct MapQOutput: Encodable {
    let query: String
    let transport: String
    let origin: Origin
    let results: [PlaceResult]
}

struct ErrorOutput: Encodable {
    let error: String
}

// MARK: - Haversine Distance

func haversineDistanceMiles(
    lat1: Double, lon1: Double,
    lat2: Double, lon2: Double
) -> Double {
    let R = 3958.8 // Earth radius in miles
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
        * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c
}

// MARK: - Output Helpers

func writeError(_ message: String) {
    let output = ErrorOutput(error: message)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(output),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

func writeStderr(_ message: String) {
    let data = (message + "\n").data(using: .utf8)!
    FileHandle.standardError.write(data)
}

// MARK: - Apple Maps Query (callback-based)

// MARK: - Address Formatting

func formatAddress(from placemark: MKPlacemark) -> String {
    var parts: [String] = []
    if let subThoroughfare = placemark.subThoroughfare {
        parts.append(subThoroughfare)
    }
    if let thoroughfare = placemark.thoroughfare {
        if parts.isEmpty {
            parts.append(thoroughfare)
        } else {
            parts[0] = parts[0] + " " + thoroughfare
        }
    }
    if let locality = placemark.locality {
        parts.append(locality)
    }
    if let administrativeArea = placemark.administrativeArea {
        parts.append(administrativeArea)
    }
    if let postalCode = placemark.postalCode {
        parts.append(postalCode)
    }
    return parts.joined(separator: ", ")
}

// MARK: - Transport Type Label

func transportLabel(_ transportType: MKDirectionsTransportType) -> String {
    switch transportType {
    case .automobile:
        return "by car"
    case .walking:
        return "on foot"
    case .transit:
        return "by transit"
    default:
        return "by car"
    }
}

// MARK: - Argument Parsing

func parseArgs() -> (lat: Double, lon: Double, query: String, transport: MKDirectionsTransportType, transportName: String, count: Int)? {
    let args = CommandLine.arguments
    var latOpt: Double? = nil
    var lonOpt: Double? = nil
    var queryOpt: String? = nil
    var transportOpt: MKDirectionsTransportType = .automobile
    var transportName: String = "automobile"
    var count: Int = 3

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--lat":
            i += 1
            if i < args.count, let v = Double(args[i]) { latOpt = v }
        case "--lon":
            i += 1
            if i < args.count, let v = Double(args[i]) { lonOpt = v }
        case "--query":
            i += 1
            if i < args.count { queryOpt = args[i] }
        case "--transport":
            i += 1
            if i < args.count {
                let t = args[i]
                transportName = t
                switch t {
                case "automobile": transportOpt = .automobile
                case "walking":    transportOpt = .walking
                case "transit":    transportOpt = .transit
                default:           transportOpt = .automobile; transportName = "automobile"
                }
            }
        case "--count":
            i += 1
            if i < args.count, let v = Int(args[i]) { count = v }
        default:
            break
        }
        i += 1
    }

    guard let lat = latOpt, let lon = lonOpt, let query = queryOpt else {
        return nil
    }
    return (lat, lon, query, transportOpt, transportName, count)
}

// MARK: - Entry Point

guard let parsed = parseArgs() else {
    let usage = "Usage: mapq --lat FLOAT --lon FLOAT --query STRING [--transport automobile|walking|transit] [--count INT]"
    FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
    exit(1)
}

let (lat, lon, query, transportOpt, transportName, count) = parsed
let origin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
let originMapItem = MKMapItem(placemark: MKPlacemark(coordinate: origin))

// State machine: 0=searching, 1=routing, 2=done
var phase = 0
var exitCode: Int32 = 0

// Step 1: Search for nearby places
let searchReq = MKLocalSearch.Request()
searchReq.naturalLanguageQuery = query
searchReq.region = MKCoordinateRegion(
    center: origin,
    latitudinalMeters: 16000,
    longitudinalMeters: 16000
)

MKLocalSearch(request: searchReq).start { response, error in
    if let error = error {
        writeError(error.localizedDescription)
        exitCode = 1; phase = 2; return
    }
    guard let items = response?.mapItems, !items.isEmpty else {
        writeError("No results found for '\(query)'")
        exitCode = 1; phase = 2; return
    }

    // Sort by straight-line distance, take top N
    let sorted = items.sorted { a, b in
        haversineDistanceMiles(lat1: lat, lon1: lon,
                               lat2: a.placemark.coordinate.latitude,
                               lon2: a.placemark.coordinate.longitude)
        < haversineDistanceMiles(lat1: lat, lon1: lon,
                                  lat2: b.placemark.coordinate.latitude,
                                  lon2: b.placemark.coordinate.longitude)
    }
    let top = Array(sorted.prefix(count))

    // Step 2: Get directions for each result
    phase = 1
    var placeResults: [PlaceResult] = []
    var remaining = top.count

    for item in top {
        let coord = item.placemark.coordinate
        let slMiles = haversineDistanceMiles(
            lat1: lat, lon1: lon, lat2: coord.latitude, lon2: coord.longitude
        )

        let dirReq = MKDirections.Request()
        dirReq.source = originMapItem
        dirReq.destination = item
        dirReq.transportType = transportOpt

        MKDirections(request: dirReq).calculate { dirResponse, dirError in
            var routeMiles = slMiles
            var travelMinutes = 0

            if let route = dirResponse?.routes.first {
                routeMiles = route.distance / 1609.344
                travelMinutes = Int((route.expectedTravelTime / 60).rounded())
            } else if let dirError = dirError {
                writeStderr("Warning: directions failed for \(item.name ?? "unknown"): \(dirError.localizedDescription)")
            }

            let label = transportLabel(transportOpt)
            let textSummary = String(format: "%.1f mi, %d min %@", routeMiles, travelMinutes, label)
            let address = formatAddress(from: item.placemark)

            let result = PlaceResult(
                name: item.name ?? "Unknown",
                address: address,
                latitude: coord.latitude,
                longitude: coord.longitude,
                straight_line_miles: (slMiles * 10).rounded() / 10,
                route_miles: (routeMiles * 10).rounded() / 10,
                travel_minutes: travelMinutes,
                phone: item.phoneNumber?.isEmpty == false ? item.phoneNumber : nil,
                url: item.url?.absoluteString,
                text_summary: textSummary
            )
            placeResults.append(result)

            remaining -= 1
            if remaining == 0 {
                // Sort results by route distance
                let sortedResults = placeResults.sorted { $0.route_miles < $1.route_miles }

                let output = MapQOutput(
                    query: query,
                    transport: transportName,
                    origin: Origin(latitude: lat, longitude: lon),
                    results: sortedResults
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                if let data = try? encoder.encode(output),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
                phase = 2
            }
        }
    }
}

// Pump RunLoop until done (15s timeout)
let deadline = Date().addingTimeInterval(15)
while phase < 2 && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

if phase < 2 {
    writeError("Request timed out after 15 seconds")
    exitCode = 1
}

exit(exitCode)
