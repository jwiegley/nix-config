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

// MARK: - Apple Maps Async Wrappers

func searchNearby(query: String, coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem] {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.region = MKCoordinateRegion(
        center: coordinate,
        latitudinalMeters: 16000,
        longitudinalMeters: 16000
    )

    return try await withCheckedThrowingContinuation { continuation in
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else if let response = response {
                continuation.resume(returning: response.mapItems)
            } else {
                continuation.resume(returning: [])
            }
        }
    }
}

func getDirections(
    from source: MKMapItem,
    to destination: MKMapItem,
    transportType: MKDirectionsTransportType
) async throws -> MKRoute? {
    let request = MKDirections.Request()
    request.source = source
    request.destination = destination
    request.transportType = transportType

    return try await withCheckedThrowingContinuation { continuation in
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: response?.routes.first)
            }
        }
    }
}

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

// MARK: - Entry Point (main.swift top-level code, RunLoop on main thread)

// Parse args synchronously
guard let parsed = parseArgs() else {
    let usage = "Usage: mapq --lat FLOAT --lon FLOAT --query STRING [--transport automobile|walking|transit] [--count INT]"
    FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
    exit(1)
}

let (lat, lon, query, transportOpt, transportName, count) = parsed

let origin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
let originMapItem = MKMapItem(placemark: MKPlacemark(coordinate: origin))

// Run async work on a background dispatch queue, pump main RunLoop manually
// so that MapKit callbacks (which dispatch to main thread) can fire.
var done = false
var exitCode: Int32 = 0

DispatchQueue.global().async {
    // Create a new Task that runs the async work
    let task = Task {
        do {
            let results: [PlaceResult] = try await withThrowingTaskGroup(of: [PlaceResult].self) { group in
                group.addTask {
                    let items = try await searchNearby(query: query, coordinate: origin)

                    if items.isEmpty {
                        throw NSError(
                            domain: "MapQ",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No results found for '\(query)'"]
                        )
                    }

                    let sorted = items.sorted { a, b in
                        let dA = haversineDistanceMiles(
                            lat1: lat, lon1: lon,
                            lat2: a.placemark.coordinate.latitude,
                            lon2: a.placemark.coordinate.longitude
                        )
                        let dB = haversineDistanceMiles(
                            lat1: lat, lon1: lon,
                            lat2: b.placemark.coordinate.latitude,
                            lon2: b.placemark.coordinate.longitude
                        )
                        return dA < dB
                    }

                    let top = Array(sorted.prefix(count))

                    var placeResults: [PlaceResult] = []
                    for item in top {
                        let coord = item.placemark.coordinate
                        let slMiles = haversineDistanceMiles(
                            lat1: lat, lon1: lon,
                            lat2: coord.latitude, lon2: coord.longitude
                        )

                        var routeMiles: Double = slMiles
                        var travelMinutes: Int = 0

                        do {
                            if let route = try await getDirections(
                                from: originMapItem,
                                to: item,
                                transportType: transportOpt
                            ) {
                                routeMiles = route.distance / 1609.344
                                travelMinutes = Int((route.expectedTravelTime / 60).rounded())
                            }
                        } catch {
                            writeStderr("Warning: directions failed for \(item.name ?? "unknown"): \(error.localizedDescription)")
                        }

                        let label = transportLabel(transportOpt)
                        let textSummary = String(
                            format: "%.1f mi, %d min %@",
                            routeMiles, travelMinutes, label
                        )

                        let address = formatAddress(from: item.placemark)
                        let phoneNumber: String? = item.phoneNumber?.isEmpty == false ? item.phoneNumber : nil
                        let urlString: String? = item.url?.absoluteString

                        let result = PlaceResult(
                            name: item.name ?? "Unknown",
                            address: address,
                            latitude: coord.latitude,
                            longitude: coord.longitude,
                            straight_line_miles: (slMiles * 10).rounded() / 10,
                            route_miles: (routeMiles * 10).rounded() / 10,
                            travel_minutes: travelMinutes,
                            phone: phoneNumber,
                            url: urlString,
                            text_summary: textSummary
                        )
                        placeResults.append(result)
                    }
                    return placeResults
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw NSError(
                        domain: "MapQ",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Request timed out after 15 seconds"]
                    )
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            let output = MapQOutput(
                query: query,
                transport: transportName,
                origin: Origin(latitude: lat, longitude: lon),
                results: results
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(output)
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }

        } catch {
            writeError(error.localizedDescription)
            exitCode = 1
        }

        // Signal completion from main thread
        DispatchQueue.main.async {
            done = true
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }
    _ = task
}

// Pump the main RunLoop so MapKit callbacks can fire
while !done {
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
}

exit(exitCode)
