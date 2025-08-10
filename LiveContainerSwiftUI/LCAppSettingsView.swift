//
//  LCAppSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/9/16.
//

import Foundation
import SwiftUI
import CoreLocation
import MapKit
@preconcurrency import AVFoundation
import AVKit
import PhotosUI
import Photos


// MARK: GPS Settings Section
struct GPSSettingsSection: View {
    @Binding var spoofGPS: Bool
    @Binding var latitude: CLLocationDegrees
    @Binding var longitude: CLLocationDegrees
    @Binding var altitude: CLLocationDistance
    @Binding var locationName: String
    
    @State private var showMapPicker = false
    @State private var showCityPicker = false
    @State private var isEditingLocationName = false
    
    var body: some View {
        Section {
            Toggle(isOn: $spoofGPS) {
                HStack {
                        Image(systemName: "location")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text("Spoof GPS Location")
                    }
            }
            
            if spoofGPS {
                VStack(alignment: .leading, spacing: 12) {
                    // Location name field
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Location Name")
                                .font(.headline)
                            Spacer()
                            Button(isEditingLocationName ? "Done" : "Edit") {
                                isEditingLocationName.toggle()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                        
                        if isEditingLocationName {
                            TextField("Enter location name", text: $locationName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(locationName.isEmpty ? "Unknown Location" : locationName)
                                .foregroundColor(locationName.isEmpty ? .secondary : .primary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    Divider()
                    
                    // Quick location picker buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            showMapPicker = true
                        }) {
                            Label("Map Picker", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            showCityPicker = true
                        }) {
                            Label("City Picker", systemImage: "building.2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider()
                    
                    // Manual coordinate entry
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            TextField("37.7749", value: $latitude, format: .number.precision(.fractionLength(6)))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 140)
                        }
                        
                        HStack {
                            Text("Longitude")
                            Spacer()
                            TextField("-122.4194", value: $longitude, format: .number.precision(.fractionLength(6)))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 140)
                        }
                        
                        HStack {
                            Text("Altitude (m)")
                            Spacer()
                            TextField("0.0", value: $altitude, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 100)
                        }
                    }
                    
                    // Current location display
                    if latitude != 0 || longitude != 0 {
                        HStack {
                            Image(systemName: "location")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coordinates:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(latitude, specifier: "%.6f"), \(longitude, specifier: "%.6f")")
                                    .font(.footnote)
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            Text("Location Settings")
        } footer: {
            if spoofGPS {
                Text("When enabled, this app will receive the specified GPS coordinates instead of the device's actual location.")
            }
        }
        .sheet(isPresented: $showMapPicker) {
            LCMapPickerView(latitude: $latitude, longitude: $longitude, locationName: $locationName, isPresented: $showMapPicker)
        }
        .sheet(isPresented: $showCityPicker) {
            LCCityPickerView(latitude: $latitude, longitude: $longitude, locationName: $locationName, isPresented: $showCityPicker)
        }
        .onAppear {
            // Only set default name if it's empty
            if locationName.isEmpty {
                locationName = "Unknown Location"
            }
        }
    }
}

struct LCMapPickerView: View {
    @Binding var latitude: CLLocationDegrees
    @Binding var longitude: CLLocationDegrees
    @Binding var locationName: String
    @Binding var isPresented: Bool
    
    @State private var region: MKCoordinateRegion
    @State private var pinLocation: CLLocationCoordinate2D
    @State private var currentLocationName = "Loading..."
    @State private var lastGeocodedCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    
    init(latitude: Binding<CLLocationDegrees>, longitude: Binding<CLLocationDegrees>, locationName: Binding<String>, isPresented: Binding<Bool>) {
        self._latitude = latitude
        self._longitude = longitude
        self._locationName = locationName
        self._isPresented = isPresented
        
        let coord = CLLocationCoordinate2D(latitude: latitude.wrappedValue, longitude: longitude.wrappedValue)
        self._region = State(initialValue: MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
        self._pinLocation = State(initialValue: coord)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Map(coordinateRegion: $region, annotationItems: [MapPin(coordinate: pinLocation)]) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: .red)
                }
                .onChange(of: region.center.latitude) { _ in
                    handleRegionChange()
                }
                .onChange(of: region.center.longitude) { _ in
                    handleRegionChange()
                }
                .overlay(
                    // Crosshair in center for better precision
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "target")
                                .font(.title2)
                                .foregroundColor(.red)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 30, height: 30)
                                )
                            Spacer()
                        }
                    }
                    .allowsHitTesting(false)
                )
                
                // Show current location name
                VStack(spacing: 4) {
                    Text("Current Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentLocationName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Coordinates")
                            .font(.headline)
                        Spacer()
                    }
                    
                    HStack {
                        Text("Latitude")
                        Spacer()
                        TextField("Latitude", value: $pinLocation.latitude, format: .number.precision(.fractionLength(6)))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 120)
                            .onChange(of: pinLocation.latitude) { newValue in
                                region.center.latitude = newValue
                            }
                    }
                    
                    HStack {
                        Text("Longitude")
                        Spacer()
                        TextField("Longitude", value: $pinLocation.longitude, format: .number.precision(.fractionLength(6)))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 120)
                            .onChange(of: pinLocation.longitude) { newValue in
                                region.center.longitude = newValue
                            }
                    }
                    
                    // Add a button to capture the current map center
                    Button(action: {
                        pinLocation = region.center
                    }) {
                        Label("Capture Location", systemImage: "target")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding()
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("OK") {
                    latitude = pinLocation.latitude
                    longitude = pinLocation.longitude
                    locationName = currentLocationName // Use the geocoded name
                    isPresented = false
                }
            )
        }
        .onAppear {
            reverseGeocode(coordinate: region.center)
        }
    }
    
    private func handleRegionChange() {
        let currentCenter = region.center
        let distance = sqrt(pow(currentCenter.latitude - lastGeocodedCoordinate.latitude, 2) + 
                           pow(currentCenter.longitude - lastGeocodedCoordinate.longitude, 2))
        
        // Only geocode if moved significantly (about 100m)
        if distance > 0.001 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Double-check we haven't moved again
                let finalCenter = region.center
                let finalDistance = sqrt(pow(finalCenter.latitude - currentCenter.latitude, 2) + 
                                       pow(finalCenter.longitude - currentCenter.longitude, 2))
                
                if finalDistance < 0.0001 { // Still in roughly the same place
                    reverseGeocode(coordinate: finalCenter)
                }
            }
        }
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        lastGeocodedCoordinate = coordinate
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    var locationComponents: [String] = []
                    
                    if let locality = placemark.locality {
                        locationComponents.append(locality)
                    }
                    if let administrativeArea = placemark.administrativeArea {
                        locationComponents.append(administrativeArea)
                    }
                    if let country = placemark.country {
                        locationComponents.append(country)
                    }
                    
                    if !locationComponents.isEmpty {
                        currentLocationName = locationComponents.joined(separator: ", ")
                    } else {
                        currentLocationName = "Unknown Location"
                    }
                } else {
                    currentLocationName = "Unknown Location"
                }
            }
        }
    }
}

struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct City {
    let name: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
}

struct LCCityPickerView: View {
    @Binding var latitude: CLLocationDegrees
    @Binding var longitude: CLLocationDegrees
    @Binding var locationName: String
    @Binding var isPresented: Bool
    
    static let cities = [
        City(name: "New York", latitude: 40.7128, longitude: -74.0060),
        City(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437),
        City(name: "Chicago", latitude: 41.8781, longitude: -87.6298),
        City(name: "Houston", latitude: 29.7604, longitude: -95.3698),
        City(name: "Phoenix", latitude: 33.4484, longitude: -112.0740),
        City(name: "Philadelphia", latitude: 39.9526, longitude: -75.1652),
        City(name: "San Antonio", latitude: 29.4241, longitude: -98.4936),
        City(name: "San Diego", latitude: 32.7157, longitude: -117.1611),
        City(name: "Dallas", latitude: 32.7767, longitude: -96.7970),
        City(name: "San Jose", latitude: 37.3382, longitude: -121.8863),
        City(name: "Austin", latitude: 30.2672, longitude: -97.7431),
        City(name: "Jacksonville", latitude: 30.3322, longitude: -81.6557),
        City(name: "San Francisco", latitude: 37.7749, longitude: -122.4194),
        City(name: "Columbus", latitude: 39.9612, longitude: -82.9988),
        City(name: "Fort Worth", latitude: 32.7555, longitude: -97.3308),
        City(name: "Indianapolis", latitude: 39.7684, longitude: -86.1581),
        City(name: "Charlotte", latitude: 35.2271, longitude: -80.8431),
        City(name: "Seattle", latitude: 47.6062, longitude: -122.3321),
        City(name: "Denver", latitude: 39.7392, longitude: -104.9903),
        City(name: "Washington DC", latitude: 38.9072, longitude: -77.0369),
        City(name: "Boston", latitude: 42.3601, longitude: -71.0589),
        City(name: "El Paso", latitude: 31.7619, longitude: -106.4850),
        City(name: "Detroit", latitude: 42.3314, longitude: -83.0458),
        City(name: "Nashville", latitude: 36.1627, longitude: -86.7816),
        City(name: "Portland", latitude: 45.5152, longitude: -122.6784),
        City(name: "Memphis", latitude: 35.1495, longitude: -90.0490),
        City(name: "Oklahoma City", latitude: 35.4676, longitude: -97.5164),
        City(name: "Las Vegas", latitude: 36.1699, longitude: -115.1398),
        City(name: "Louisville", latitude: 38.2527, longitude: -85.7585),
        City(name: "Baltimore", latitude: 39.2904, longitude: -76.6122),
        City(name: "Milwaukee", latitude: 43.0389, longitude: -87.9065),
        City(name: "Albuquerque", latitude: 35.0844, longitude: -106.6504),
        City(name: "Tucson", latitude: 32.2226, longitude: -110.9747),
        City(name: "Fresno", latitude: 36.7378, longitude: -119.7871),
        City(name: "Mesa", latitude: 33.4152, longitude: -111.8315),
        City(name: "Sacramento", latitude: 38.5816, longitude: -121.4944),
        City(name: "Atlanta", latitude: 33.7490, longitude: -84.3880),
        City(name: "Kansas City", latitude: 39.0997, longitude: -94.5786),
        City(name: "Colorado Springs", latitude: 38.8339, longitude: -104.8214),
        City(name: "Miami", latitude: 25.7617, longitude: -80.1918),
        City(name: "Raleigh", latitude: 35.7796, longitude: -78.6382),
        City(name: "Omaha", latitude: 41.2524, longitude: -95.9980),
        City(name: "Long Beach", latitude: 33.7701, longitude: -118.1937),
        City(name: "Virginia Beach", latitude: 36.8529, longitude: -75.9780),
        City(name: "Oakland", latitude: 37.8044, longitude: -122.2711),
        City(name: "Minneapolis", latitude: 44.9778, longitude: -93.2650),
        City(name: "Tulsa", latitude: 36.1540, longitude: -95.9928),
        City(name: "Arlington", latitude: 32.7357, longitude: -97.1081),
        City(name: "Tampa", latitude: 27.9506, longitude: -82.4572),
        City(name: "New Orleans", latitude: 29.9511, longitude: -90.0715),
        
        // International cities
        City(name: "London", latitude: 51.5074, longitude: -0.1278),
        City(name: "Paris", latitude: 48.8566, longitude: 2.3522),
        City(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        City(name: "Berlin", latitude: 52.5200, longitude: 13.4050),
        City(name: "Madrid", latitude: 40.4168, longitude: -3.7038),
        City(name: "Rome", latitude: 41.9028, longitude: 12.4964),
        City(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041),
        City(name: "Vienna", latitude: 48.2082, longitude: 16.3738),
        City(name: "Prague", latitude: 50.0755, longitude: 14.4378),
        City(name: "Budapest", latitude: 47.4979, longitude: 19.0402),
        City(name: "Warsaw", latitude: 52.2297, longitude: 21.0122),
        City(name: "Stockholm", latitude: 59.3293, longitude: 18.0686),
        City(name: "Oslo", latitude: 59.9139, longitude: 10.7522),
        City(name: "Copenhagen", latitude: 55.6761, longitude: 12.5683),
        City(name: "Helsinki", latitude: 60.1699, longitude: 24.9384),
        City(name: "Dublin", latitude: 53.3498, longitude: -6.2603),
        City(name: "Brussels", latitude: 50.8503, longitude: 4.3517),
        City(name: "Zurich", latitude: 47.3769, longitude: 8.5417),
        City(name: "Barcelona", latitude: 41.3851, longitude: 2.1734),
        City(name: "Lisbon", latitude: 38.7223, longitude: -9.1393),
        City(name: "Athens", latitude: 37.9838, longitude: 23.7275),
        City(name: "Istanbul", latitude: 41.0082, longitude: 28.9784),
        City(name: "Moscow", latitude: 55.7558, longitude: 37.6176),
        City(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
        City(name: "Melbourne", latitude: -37.8136, longitude: 144.9631),
        City(name: "Toronto", latitude: 43.6532, longitude: -79.3832),
        City(name: "Vancouver", latitude: 49.2827, longitude: -123.1207),
        City(name: "Montreal", latitude: 45.5017, longitude: -73.5673)
    ]
    
    @State private var searchText = ""
    
    var filteredCities: [City] {
        if searchText.isEmpty {
            return Self.cities
        } else {
            return Self.cities.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredCities, id: \.name) { city in
                    Button(action: {
                        latitude = city.latitude
                        longitude = city.longitude
                        locationName = city.name // Set the city name
                        isPresented = false
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(city.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("\(city.latitude, specifier: "%.4f"), \(city.longitude, specifier: "%.4f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search cities...")
            .navigationTitle("Choose City")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                }
            )
        }
    }
}

struct SeededRandomGenerator {
    private var state: UInt64
    
    init(seed: Int) {
        self.state = UInt64(seed)
    }
    
    mutating func next() -> UInt64 {
        // Linear congruential generator (simple but effective for our use)
        state = state &* 1103515245 &+ 12345
        return state
    }
    
    mutating func nextDouble(_ min: Double, _ max: Double) -> Double {
        let normalized = Double(next() % 10000) / 9999.0 // 0.0 to 1.0
        return min + normalized * (max - min)
    }
}

// MARK: Camera Settings Section
struct CameraSettingsSection: View {
    @Binding var spoofCamera: Bool
    @Binding var spoofCameraMode: String
    @Binding var spoofCameraType: String
    @Binding var spoofCameraImagePath: String
    @Binding var spoofCameraVideoPath: String
    @Binding var spoofCameraLoop: Bool
    @Binding var spoofCameraTransformOrientation: String
    @Binding var spoofCameraTransformScale: String
    @Binding var spoofCameraTransformFlip: String
    @Binding var isProcessingVideo: Bool
    @Binding var videoProcessingProgress: Double
    @Binding var errorInfo: String
    @Binding var errorShow: Bool
    
    // Remove the callback - handle internally
    // let onVideoTransformChange: () async -> Void
    
    var body: some View {
        Section {
            Toggle(isOn: $spoofCamera) {
                HStack {
                    Image(systemName: "camera")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Spoof Camera")
                }
            }
            
            if spoofCamera {
                // Media Type Picker (keep this simple)
                Picker("Camera Type", selection: $spoofCameraType) {
                    Text("Static Image").tag("image")
                    Text("Video").tag("video")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                // Media Selection based on type
                if spoofCameraType == "image" {
                    CameraImagePickerView(
                        imagePath: $spoofCameraImagePath,
                        errorInfo: $errorInfo,
                        errorShow: $errorShow,
                        // Pass transformation bindings to image picker
                        spoofCameraMode: $spoofCameraMode,
                        spoofCameraTransformOrientation: $spoofCameraTransformOrientation,
                        spoofCameraTransformScale: $spoofCameraTransformScale,
                        spoofCameraTransformFlip: $spoofCameraTransformFlip,
                        isProcessingVideo: $isProcessingVideo,
                        videoProcessingProgress: $videoProcessingProgress
                    )
                } else {
                    CameraVideoPickerView(
                        videoPath: $spoofCameraVideoPath,
                        loopVideo: $spoofCameraLoop,
                        errorInfo: $errorInfo,
                        errorShow: $errorShow
                    )
                    
                    // ✅ NEW: Video transformations with Verified Mode as first option
                    if !spoofCameraVideoPath.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Video Transformations")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            // ✅ Verified Mode as part of transformations
                            HStack {
                                Toggle("Verified Mode", isOn: Binding(
                                    get: { spoofCameraMode == "verified" },
                                    set: { newValue in
                                        spoofCameraMode = newValue ? "verified" : "standard"
                                        Task {
                                            await processVideoTransforms()
                                        }
                                    }
                                ))
                                
                                Spacer()
                                
                                if spoofCameraMode == "verified" {
                                    Label("Anti-Detection", systemImage: "checkmark.shield")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.bottom, 4)
                            
                            if spoofCameraMode == "verified" {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                    Text("Adds Nomix-style random variations to avoid detection")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            // Standard transformation controls
                            Picker("Orientation", selection: Binding(
                                get: { spoofCameraTransformOrientation },
                                set: { newValue in
                                    spoofCameraTransformOrientation = newValue
                                    Task {
                                        await processVideoTransforms()
                                    }
                                }
                            )) {
                                Text("Original").tag("none")
                                Text("Force Portrait").tag("portrait") 
                                Text("Force Landscape").tag("landscape")
                                Text("Rotate 90°").tag("rotate90")
                                Text("Rotate 180°").tag("rotate180")
                                Text("Rotate 270°").tag("rotate270")
                            }
                            
                            Picker("Scale", selection: Binding(
                                get: { spoofCameraTransformScale },
                                set: { newValue in
                                    spoofCameraTransformScale = newValue
                                    Task {
                                        await processVideoTransforms()
                                    }
                                }
                            )) {
                                Text("Fit").tag("fit")
                                Text("Fill").tag("fill")
                                Text("Stretch").tag("stretch")
                            }
                            
                            Picker("Flip", selection: Binding(
                                get: { spoofCameraTransformFlip },
                                set: { newValue in
                                    spoofCameraTransformFlip = newValue
                                    Task {
                                        await processVideoTransforms()
                                    }
                                }
                            )) {
                                Text("None").tag("none")
                                Text("Horizontal").tag("horizontal")
                                Text("Vertical").tag("vertical")
                                Text("Both").tag("both")
                            }
                            
                            // Processing indicator
                            if isProcessingVideo {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Processing video transformations...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    ProgressView(value: videoProcessingProgress)
                                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                    
                                    Text("\(Int(videoProcessingProgress * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            
                            // Transform summary
                            if hasAnyTransforms() {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active Transformations:")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        if spoofCameraMode == "verified" {
                                            Label("Verified", systemImage: "checkmark.shield")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                        
                                        if spoofCameraTransformOrientation != "none" {
                                            Label(orientationLabel(), systemImage: "rotate.3d")
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                        }
                                        
                                        if spoofCameraTransformFlip != "none" {
                                            Label(spoofCameraTransformFlip.capitalized, systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                                                .font(.caption2)
                                                .foregroundColor(.purple)
                                        }
                                        
                                        if spoofCameraTransformScale != "fit" {
                                            Label(spoofCameraTransformScale.capitalized, systemImage: "viewfinder")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            Text("Transformations are applied when settings change. Verified mode adds random variations like Nomix.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
                
                if #unavailable(iOS 16.0) {
                    Text("Note: Photo library access requires iOS 16.0 or later. Use Files or manual path entry instead.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } header: {
            Text("Camera Settings")
        }
    }
    
    // MARK: VIDEO TRANSFORM FUNCTIONS
    
    @MainActor
    private func processVideoTransforms() async {
        guard spoofCamera && spoofCameraType == "video" && !spoofCameraVideoPath.isEmpty else {
            return
        }
        
        // Check if any transforms are applied
        let hasTransforms = hasAnyTransforms()
        
        guard hasTransforms else { return }
        
        isProcessingVideo = true
        videoProcessingProgress = 0.0
        
        do {
            let transformedPath = try await transformVideo(
                inputPath: spoofCameraVideoPath,
                orientation: spoofCameraTransformOrientation,
                scale: spoofCameraTransformScale,
                flip: spoofCameraTransformFlip,
                isVerifiedMode: spoofCameraMode == "verified"
            )
            
            spoofCameraVideoPath = transformedPath
            
        } catch {
            errorInfo = "Video transformation failed: \(error.localizedDescription)"
            errorShow = true
        }
        
        isProcessingVideo = false
    }

   private func transformVideo(
        inputPath: String,
        orientation: String,
        scale: String,
        flip: String,
        isVerifiedMode: Bool = false
    ) async throws -> String {
        
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + "_transformed.mp4"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputFileName)
        
        // Remove existing transformed file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let asset = AVAsset(url: inputURL)
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        
        // Add video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoTransform", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "VideoTransform", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
        }
        
        let duration = try await asset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        
        // Add audio track if present
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: .zero
                )
            }
        }
        
        // Calculate transform
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        let transformResult = calculateVideoTransform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            orientation: orientation,
            scale: scale,
            flip: flip,
            isVerifiedMode: isVerifiedMode
        )
        
        // Create video composition
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transformResult.transform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = transformResult.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Export with progress monitoring
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "VideoTransform", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        
        // Use withCheckedContinuation for proper async/await
        return try await withCheckedThrowingContinuation { continuation in
            // Store references to avoid capture issues
            let session = exportSession
            
            // Monitor progress in a separate task
            let progressTask = Task { @MainActor in
                while !session.status.isFinished {
                    videoProcessingProgress = Double(session.progress)
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                videoProcessingProgress = 1.0
            }
            
            session.exportAsynchronously {
                progressTask.cancel()
                
                switch session.status {
                case .completed:
                    Task { @MainActor in
                        videoProcessingProgress = 1.0
                    }
                    continuation.resume(returning: outputURL.path)
                case .failed:
                    let errorMessage = session.error?.localizedDescription ?? "Unknown export error"
                    let error = NSError(domain: "VideoTransform", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export failed: \(errorMessage)"])
                    continuation.resume(throwing: error)
                case .cancelled:
                    let error = NSError(domain: "VideoTransform", code: 5, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled"])
                    continuation.resume(throwing: error)
                default:
                    let error = NSError(domain: "VideoTransform", code: 6, userInfo: [NSLocalizedDescriptionKey: "Export in unknown state"])
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func calculateVideoTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        orientation: String,
        scale: String,
        flip: String,
        isVerifiedMode: Bool = false // Add this parameter
    ) -> (transform: CGAffineTransform, renderSize: CGSize) {
        
        var transform = preferredTransform
        var renderSize = naturalSize
        
        // Apply orientation
        switch orientation {
        case "portrait":
            if naturalSize.width > naturalSize.height {
                transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
                renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
            }
        case "landscape":
            if naturalSize.height > naturalSize.width {
                transform = transform.concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
                renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
            }
        case "rotate90":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
            renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        case "rotate180":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi))
        case "rotate270":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
            renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        default: // "none"
            break
        }
        
        // Apply flip
        switch flip {
        case "horizontal":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1))
            transform = transform.concatenating(CGAffineTransform(translationX: renderSize.width, y: 0))
        case "vertical":
            transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
            transform = transform.concatenating(CGAffineTransform(translationX: 0, y: renderSize.height))
        case "both":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: -1))
            transform = transform.concatenating(CGAffineTransform(translationX: renderSize.width, y: renderSize.height))
        default: // "none"
            break
        }
        
        // ✅ NEW: Apply Verified Mode (Nomix-style) variations
        if isVerifiedMode {
            // Generate subtle random variations to avoid detection
            let seed = Int(Date().timeIntervalSince1970) % 1000 // Change variations over time
            var rng = SeededRandomGenerator(seed: seed)
            
            // 1. Slight rotation variation (±0.5 degrees)
            let rotationVariation = rng.nextDouble(-0.5, 0.5) * .pi / 180.0
            if abs(rotationVariation) > 0.001 {
                let centerX = renderSize.width / 2
                let centerY = renderSize.height / 2
                let rotateTransform = CGAffineTransform(translationX: centerX, y: centerY)
                    .concatenating(CGAffineTransform(rotationAngle: rotationVariation))
                    .concatenating(CGAffineTransform(translationX: -centerX, y: -centerY))
                transform = transform.concatenating(rotateTransform)
            }
            
            // 2. Slight scale variation (0.98x to 1.02x)
            let scaleVariation = rng.nextDouble(0.98, 1.02)
            if abs(scaleVariation - 1.0) > 0.001 {
                let centerX = renderSize.width / 2
                let centerY = renderSize.height / 2
                let scaleTransform = CGAffineTransform(translationX: centerX, y: centerY)
                    .concatenating(CGAffineTransform(scaleX: scaleVariation, y: scaleVariation))
                    .concatenating(CGAffineTransform(translationX: -centerX, y: -centerY))
                transform = transform.concatenating(scaleTransform)
            }
            
            // 3. Small translation variation (±2 pixels)
            let translateX = rng.nextDouble(-2.0, 2.0)
            let translateY = rng.nextDouble(-2.0, 2.0)
            if abs(translateX) > 0.1 || abs(translateY) > 0.1 {
                transform = transform.concatenating(CGAffineTransform(translationX: translateX, y: translateY))
            }
            
            // 4. Slight render size variation (±1 pixel) to break fingerprinting
            let sizeVariationX = rng.nextDouble(-1.0, 1.0)
            let sizeVariationY = rng.nextDouble(-1.0, 1.0)
            renderSize = CGSize(
                width: max(1, renderSize.width + sizeVariationX),
                height: max(1, renderSize.height + sizeVariationY)
            )
            
            print("🎭 Verified mode applied: rotation=\(rotationVariation * 180 / .pi)°, scale=\(scaleVariation), translate=(\(translateX),\(translateY)), size=(\(sizeVariationX),\(sizeVariationY))")
        }
        
        return (transform, renderSize)
    }

    private func hasAnyTransforms() -> Bool {
        return spoofCameraMode == "verified" ||
            spoofCameraTransformOrientation != "none" ||
            spoofCameraTransformFlip != "none" ||
            spoofCameraTransformScale != "fit"
    }

    private func orientationLabel() -> String {
        switch spoofCameraTransformOrientation {
        case "portrait": return "Portrait"
        case "landscape": return "Landscape"
        case "rotate90": return "90°"
        case "rotate180": return "180°"
        case "rotate270": return "270°"
        default: return "Original"
        }
    }
}


// MARK: Network Settings Section
struct NetworkSettingsSection: View {
    @Binding var spoofNetwork: Bool
    @Binding var proxyHost: String
    @Binding var proxyPort: Int32
    @Binding var proxyUsername: String
    @Binding var proxyPassword: String
    
    var body: some View {
        Section {
            Toggle(isOn: $spoofNetwork) {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("SOCKS5 Proxy")
                }
            }
            
            if spoofNetwork {
                // Proxy Host
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(.gray)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text("Proxy Host")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., 127.0.0.1", text: $proxyHost)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // Proxy Port
                HStack {
                    Image(systemName: "number")
                        .foregroundColor(.gray)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text("Proxy Port")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1080", value: $proxyPort, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }
                }
                
                // Authentication (optional)
                DisclosureGroup("Authentication") {
                    HStack {
                        Image(systemName: "person")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Username")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Optional", text: $proxyUsername)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    HStack {
                        Image(systemName: "key")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Optional", text: $proxyPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
            }
        } header: {
            Text("Network Settings")
        } footer: {
            if spoofNetwork {
                Text("Routes app traffic through SOCKS5 proxy. Compatible with Shadowrocket, V2Ray, and other proxy tools.")
            } else {
                Text("Route network traffic through a SOCKS5 proxy server.")
            }
        }
    }
}

extension AVAssetExportSession.Status {
    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: Main
struct LCAppSettingsView : View{
    
    private var appInfo : LCAppInfo
    
    @ObservedObject private var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    

    @StateObject private var renameFolderInput = InputHelper()
    @StateObject private var moveToAppGroupAlert = YesNoHelper()
    @StateObject private var moveToPrivateDocAlert = YesNoHelper()
    @StateObject private var signUnsignedAlert = YesNoHelper()
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var selectUnusedContainerSheetShow = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(model: LCAppModel, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        self.appInfo = model.appInfo
        self._model = ObservedObject(wrappedValue: model)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("lc.appSettings.bundleId".loc)
                    Spacer()
                    Text(appInfo.relativeBundlePath)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                if !model.uiIsShared {
                    Menu {
                        Picker(selection: $model.uiTweakFolder , label: Text("")) {
                            Label("lc.common.none".loc, systemImage: "nosign").tag(Optional<String>(nil))
                            ForEach(tweakFolders, id:\.self) { folderName in
                                Text(folderName).tag(Optional(folderName))
                            }
                        }
                    } label: {
                        HStack {
                            Text("lc.appSettings.tweakFolder".loc)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(model.uiTweakFolder == nil ? "None" : model.uiTweakFolder!)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    
                } else {
                    HStack {
                        Text("lc.appSettings.tweakFolder".loc)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.uiTweakFolder == nil ? "lc.common.none".loc : model.uiTweakFolder!)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if !model.uiIsShared {
                    if LCUtils.isAppGroupAltStoreLike() || LCUtils.store() == .ADP {
                        Button("lc.appSettings.toSharedApp".loc) {
                            Task { await moveToAppGroup()}
                        }
                    }
                } else if sharedModel.multiLCStatus != 2 {
                    Button("lc.appSettings.toPrivateApp".loc) {
                        Task { await movePrivateDoc() }
                    }
                }
            } header: {
                Text("lc.common.data".loc)
            }
            
            Section {
                List{
                    ForEach(model.uiContainers.indices, id:\.self) { i in
                        NavigationLink {
                            LCContainerView(container: model.uiContainers[i], uiDefaultDataFolder: $model.uiDefaultDataFolder, delegate: self)
                        } label: {
                            Text(model.uiContainers[i].name)
                        }
                    }
                }
                if(model.uiContainers.count < SharedModel.keychainAccessGroupCount) {
                    Button {
                        Task{ await createFolder() }
                    } label: {
                        Text("lc.appSettings.newDataFolder".loc)
                    }
                    if(!model.uiIsShared) {
                        Button {
                            selectUnusedContainerSheetShow = true
                        } label: {
                            Text("lc.container.selectUnused".loc)
                        }
                    }
                }
                
            } header: {
                Text("lc.common.container".loc)
            }
            
            
            // MARK: GPS Settings init
            GPSSettingsSection(
                spoofGPS: $model.uiSpoofGPS,
                latitude: $model.uiSpoofLatitude,
                longitude: $model.uiSpoofLongitude,
                altitude: $model.uiSpoofAltitude,
                locationName: $model.uiSpoofLocationName
            )
            
            // MARK: Camera Settings init
            CameraSettingsSection(
                spoofCamera: $model.uiSpoofCamera,
                spoofCameraMode: $model.uiSpoofCameraMode,
                spoofCameraType: $model.uiSpoofCameraType,
                spoofCameraImagePath: $model.uiSpoofCameraImagePath,
                spoofCameraVideoPath: $model.uiSpoofCameraVideoPath,
                spoofCameraLoop: $model.uiSpoofCameraLoop,
                spoofCameraTransformOrientation: $model.uiSpoofCameraTransformOrientation,
                spoofCameraTransformScale: $model.uiSpoofCameraTransformScale,
                spoofCameraTransformFlip: $model.uiSpoofCameraTransformFlip,
                isProcessingVideo: $model.isProcessingVideo,
                videoProcessingProgress: $model.videoProcessingProgress,
                errorInfo: $errorInfo,
                errorShow: $errorShow
            )
           

            // MARK: Network Settings init
            NetworkSettingsSection(
                spoofNetwork: $model.uiSpoofNetwork,
                proxyHost: $model.uiProxyHost,
                proxyPort: $model.uiProxyPort,
                proxyUsername: $model.uiProxyUsername,
                proxyPassword: $model.uiProxyPassword
            )

            // MARK: Security Section
            Section {
                Toggle(isOn: $model.uiHideLiveContainer) {
                    Text("lc.appSettings.hideLiveContainer".loc)
                } 

                Toggle(isOn: $model.uiDontInjectTweakLoader) {
                    Text("lc.appSettings.dontInjectTweakLoader".loc)
                }
                // }.disabled(model.uiTweakLoaderInjectFailed) // don't force disable
                
                if model.uiDontInjectTweakLoader {
                    Toggle(isOn: $model.uiDontLoadTweakLoader) {
                        Text("lc.appSettings.dontLoadTweakLoader".loc)
                    }
                }
                Toggle(isOn: $model.uiBypassSSLPinning) {
                    Text("Bypass SSL Pinning")
                }
            } header: {
                Text("Security Settings")
            }
            
            Section {
                Toggle(isOn: $model.uiIsJITNeeded) {
                    Text("lc.appSettings.launchWithJit".loc)
                }
            } footer: {
                Text("lc.appSettings.launchWithJitDesc".loc)
            }

            Section {
                Toggle(isOn: $model.uiIsLocked) {
                    Text("lc.appSettings.lockApp".loc)
                }
                .onChange(of: model.uiIsLocked, perform: { newValue in
                    Task { await model.setLocked(newLockState: newValue) }
                })

                if model.uiIsLocked {
                    Toggle(isOn: $model.uiIsHidden) {
                        Text("lc.appSettings.hideApp".loc)
                    }
                    .onChange(of: model.uiIsHidden, perform: { _ in
                        Task { await toggleHidden() }
                    })
                    .transition(.opacity.combined(with: .slide)) 
                }
            } footer: {
                if model.uiIsLocked {
                    Text("lc.appSettings.hideAppDesc".loc)
                        .transition(.opacity.combined(with: .slide))
                }
            }

            Section {
                NavigationLink {
                    if let supportedLanguage = model.supportedLanguages {
                        Form {
                            Picker(selection: $model.uiSelectedLanguage) {
                                Text("lc.common.auto".loc).tag("")
                                
                                ForEach(supportedLanguage, id:\.self) { language in
                                    if language != "Base" {
                                        VStack(alignment: .leading) {
                                            Text(Locale(identifier: language).localizedString(forIdentifier: language) ?? language)
                                            Text("\(Locale.current.localizedString(forIdentifier: language) ?? "") - \(language)")
                                                .font(.footnote)
                                                .foregroundStyle(.gray)
                                        }
                                        .tag(language)
                                    }

                                }
                            } label: {
                                Text("lc.common.language".loc)
                            }
                            .pickerStyle(.inline)
                        }

                    } else {
                        Text("lc.common.loading".loc)
                            .onAppear() {
                                Task{ loadSupportedLanguages() }
                            }
                    }
                } label: {
                    HStack {
                        Text("lc.common.language".loc)
                        Spacer()
                        if model.uiSelectedLanguage == "" {
                            Text("lc.common.auto".loc)
                                .foregroundStyle(.gray)
                        } else {
                            Text(Locale.current.localizedString(forIdentifier: model.uiSelectedLanguage) ?? model.uiSelectedLanguage)
                                .foregroundStyle(.gray)
                        }
                    }
                    
                }
            }
            
            Section {
                Toggle(isOn: $model.uiUseLCBundleId) {
                    Text("lc.appSettings.useLCBundleId".loc)
                }
            } header: {
                Text("lc.appSettings.fixes".loc)
            } footer: {
                Text("lc.appSettings.useLCBundleIdDesc".loc)
            }
            
            if SharedModel.isPhone {
                Section {
                    Picker(selection: $model.uiOrientationLock) {
                        Text("lc.common.disabled".loc).tag(LCOrientationLock.Disabled)
                        Text("lc.apppSettings.orientationLock.landscape".loc).tag(LCOrientationLock.Landscape)
                        Text("lc.apppSettings.orientationLock.portrait".loc).tag(LCOrientationLock.Portrait)
                    } label: {
                        Text("lc.apppSettings.orientationLock".loc)
                    }
                }
            }
            
            Section {
                Toggle(isOn: $model.uiSpoofSDKVersion) {
                    Text("lc.appSettings.spoofSDKVersion".loc)
                }
            } footer: {
                Text("lc.appSettings.fspoofSDKVersionDesc".loc)
            }

            
            Section {
                Toggle(isOn: $model.uiDoSymlinkInbox) {
                    Text("lc.appSettings.fixFilePicker".loc)
                }
            } footer: {
                Text("lc.appSettings.fixFilePickerDesc".loc)
            }
            
            Section {
                Button("lc.appSettings.forceSign".loc) {
                    Task { await forceResign() }
                }
                .disabled(model.isAppRunning)
            } footer: {
                Text("lc.appSettings.forceSignDesc".loc)
            }
            
            Section {
                HStack {
                    Text("lc.appList.sort.lastLaunched".loc)
                    Spacer()
                    Text(formatDate(date: appInfo.lastLaunched))
                        .foregroundStyle(.gray)
                }
                HStack {
                    Text("lc.appList.sort.installationDate".loc)
                    Spacer()
                    Text(formatDate(date: appInfo.installationDate))
                        .foregroundStyle(.gray)
                }
            } header: {
                Text("lc.common.statistics")
            }

        }
        .navigationTitle(appInfo.displayName())
        .navigationBarTitleDisplayMode(.inline)
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        
        .textFieldAlert(
            isPresented: $renameFolderInput.show,
            title: "lc.common.enterNewFolderName".loc,
            text: $renameFolderInput.initVal,
            placeholder: "",
            action: { newText in
                renameFolderInput.close(result: newText!)
            },
            actionCancel: {_ in
                renameFolderInput.close(result: "")
            }
        )
        .alert("lc.appSettings.toSharedApp".loc, isPresented: $moveToAppGroupAlert.show) {
            Button {
                self.moveToAppGroupAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToAppGroupAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toSharedAppDesc".loc)
        }
        .alert("lc.appSettings.toPrivateApp".loc, isPresented: $moveToPrivateDocAlert.show) {
            Button {
                self.moveToPrivateDocAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToPrivateDocAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toPrivateAppDesc".loc)
        }
        .alert("lc.appSettings.forceSign".loc, isPresented: $signUnsignedAlert.show) {
            Button {
                self.signUnsignedAlert.close(result: true)
            } label: {
                Text("lc.common.ok".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.signUnsignedAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.signUnsignedDesc".loc)
        }
        .sheet(isPresented: $selectUnusedContainerSheetShow) {
            LCSelectContainerView(isPresent: $selectUnusedContainerSheetShow, delegate: self)
        }
    }

    func createFolder() async {
        let newName = NSUUID().uuidString
        guard let displayName = await renameFolderInput.open(initVal: newName), displayName != "" else {
            return
        }
        let fm = FileManager()
        let dest : URL
        if model.uiIsShared {
            dest = LCPath.lcGroupDataPath.appendingPathComponent(newName)
        } else {
            dest = LCPath.dataPath.appendingPathComponent(newName)
        }
        
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        self.appDataFolders.append(newName)
        let newContainer = LCContainer(folderName: newName, name: displayName, isShared: model.uiIsShared, isolateAppGroup: true)
        // assign keychain group
        var keychainGroupSet : Set<Int> = Set(minimumCapacity: 3)
        for i in 0..<SharedModel.keychainAccessGroupCount {
            keychainGroupSet.insert(i)
        }
        for container in model.uiContainers {
            keychainGroupSet.remove(container.keychainGroupId)
        }
        guard let freeKeyChainGroup = keychainGroupSet.randomElement() else {
            errorInfo = "lc.container.notEnoughKeychainGroup".loc
            errorShow = true
            return
        }
        
        model.uiContainers.append(newContainer)
        if model.uiSelectedContainer == nil {
            model.uiSelectedContainer = newContainer;
        }
        if model.uiDefaultDataFolder == nil {
            model.uiDefaultDataFolder = newName
            appInfo.dataUUID = newName
        }
        appInfo.containers = model.uiContainers;
        newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: freeKeyChainGroup)
    }

    func moveToAppGroup() async {
        guard let result = await moveToAppGroupAlert.open(), result else {
            return
        }
        
        do {
            try LCPath.ensureAppGroupPaths()
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            for container in model.uiContainers {
                try fm.moveItem(at: LCPath.dataPath.appendingPathComponent(container.folderName),
                                to: LCPath.lcGroupDataPath.appendingPathComponent(container.folderName))
                appDataFolders.removeAll(where: { s in
                    return s == container.folderName
                })
            }
            if let tweakFolder = appInfo.tweakFolder, tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.tweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.removeAll(where: { s in
                    return s == tweakFolder
                })
            }
            appInfo.setBundlePath(LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = true
            model.uiIsShared = true
            for container in model.uiContainers {
                container.isShared = true
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func movePrivateDoc() async {
        for container in appInfo.containers {
            if let runningLC = LCUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {                
                errorInfo = "lc.appSettings.appOpenInOtherLc %@ %@".localizeWithFormat(runningLC, runningLC)
                errorShow = true
                return
            }
        }

        guard let result = await moveToPrivateDocAlert.open(), result else {
            return
        }
        
        do {
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            for container in model.uiContainers {
                try fm.moveItem(at: LCPath.lcGroupDataPath.appendingPathComponent(container.folderName),
                                to: LCPath.dataPath.appendingPathComponent(container.folderName))
                appDataFolders.append(container.folderName)
            }
            if let tweakFolder = appInfo.tweakFolder, tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.tweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.append(tweakFolder)
                model.uiTweakFolder = tweakFolder
            }
            appInfo.setBundlePath(LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = false
            model.uiIsShared = false
            for container in model.uiContainers {
                container.isShared = false
            }
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
        }
        
    }
    
    func loadSupportedLanguages() {
        do {
            try model.loadSupportedLanguages()
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
    }
    
    func toggleHidden() async {
        await model.toggleHidden()
    }
    
    func forceResign() async {
        if model.uiDontSign {
            guard let result = await signUnsignedAlert.open(), result else {
                return
            }
            model.uiDontSign = false
        }
        
        do {
            try await model.forceResign()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func formatDate(date: Date?) -> String {
        guard let date else {
            return "lc.common.unknown".loc
        }
        
        let formatter1 = DateFormatter()
        formatter1.dateStyle = .short
        formatter1.timeStyle = .medium
        return formatter1.string(from: date)
    
    }
}



extension LCAppSettingsView : LCContainerViewDelegate {
    func getBundleId() -> String {
        return model.appInfo.bundleIdentifier()!
    }
    
    func unbindContainer(container: LCContainer) {
        model.uiContainers.removeAll { c in
            c === container
        }
        
        // if the deleted container is the default one, we change to another one
        if container.folderName == model.uiDefaultDataFolder && !model.uiContainers.isEmpty{
            setDefaultContainer(container: model.uiContainers[0])
        }
        // if the deleted container is the selected one, we change to the default one
        if model.uiSelectedContainer === container && !model.uiContainers.isEmpty {
            for container in model.uiContainers {
                if container.folderName == model.uiDefaultDataFolder {
                    model.uiSelectedContainer = container
                    break
                }
            }
        }
        
        if model.uiContainers.isEmpty {
            model.uiSelectedContainer = nil
            model.uiDefaultDataFolder = nil
            appInfo.dataUUID = nil
        }
        appInfo.containers = model.uiContainers
    }
    
    func setDefaultContainer(container newDefaultContainer: LCContainer ) {
        if model.uiSelectedContainer?.folderName == model.uiDefaultDataFolder {
            model.uiSelectedContainer = newDefaultContainer
        }
        
        appInfo.dataUUID = newDefaultContainer.folderName
        model.uiDefaultDataFolder = newDefaultContainer.folderName
    }
    
    func saveContainer(container: LCContainer) {
        container.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: container.keychainGroupId)
        appInfo.containers = model.uiContainers
        model.objectWillChange.send()
    }
    
    func getSettingsBundle() -> Bundle? {
        return Bundle(url: URL(fileURLWithPath: appInfo.bundlePath()).appendingPathComponent("Settings.bundle"))
    }
    
    func getContainerURL(container: LCContainer) -> URL {
        let preferencesFolderUrl = container.containerURL.appendingPathComponent("Library/Preferences")
        let fm = FileManager.default
        do {
            let doExist = fm.fileExists(atPath: preferencesFolderUrl.path)
            if !doExist {
                try fm.createDirectory(at: preferencesFolderUrl, withIntermediateDirectories: true)
            }

        } catch {
            errorInfo = "Cannot create Library/Preferences folder!".loc
            errorShow = true
        }
        return container.containerURL
    }
    
}

extension LCAppSettingsView : LCSelectContainerViewDelegate {
    func addContainers(containers: Set<String>) {
        if containers.count + model.uiContainers.count > SharedModel.keychainAccessGroupCount {
            errorInfo = "lc.container.tooMuchContainers".loc
            errorShow = true
            return
        }
        
        for folderName in containers {
            let newContainer = LCContainer(folderName: folderName, name: folderName, isShared: false, isolateAppGroup: true)
            newContainer.loadName()
            if newContainer.keychainGroupId == -1 {
                // assign keychain group for old containers
                var keychainGroupSet : Set<Int> = Set(minimumCapacity: SharedModel.keychainAccessGroupCount)
                for i in 0..<SharedModel.keychainAccessGroupCount {
                    keychainGroupSet.insert(i)
                }
                for container in model.uiContainers {
                    keychainGroupSet.remove(container.keychainGroupId)
                }
                guard let freeKeyChainGroup = keychainGroupSet.randomElement() else {
                    errorInfo = "lc.container.notEnoughKeychainGroup".loc
                    errorShow = true
                    return
                }
                newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: freeKeyChainGroup)
            }

            
            model.uiContainers.append(newContainer)
            if model.uiSelectedContainer == nil {
                model.uiSelectedContainer = newContainer;
            }
            if model.uiDefaultDataFolder == nil {
                model.uiDefaultDataFolder = folderName
                appInfo.dataUUID = folderName
            }


        }
        appInfo.containers = model.uiContainers;

    }
}

struct CameraImagePickerView: View {
    @Binding var imagePath: String
    @Binding var errorInfo: String
    @Binding var errorShow: Bool
    
    // Transformation bindings
    @Binding var spoofCameraMode: String
    @Binding var spoofCameraTransformOrientation: String
    @Binding var spoofCameraTransformScale: String
    @Binding var spoofCameraTransformFlip: String
    @Binding var isProcessingVideo: Bool
    @Binding var videoProcessingProgress: Double
    
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: Any? = nil
    @State private var previewImage: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current image display
            if !imagePath.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Header with clear button
                    HStack {
                        Text("Current Image:")
                            .font(.headline)
                        Spacer()
                        Button(action: clearImage) {
                            Text("Clear")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Image preview
                    if let previewImage = previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        HStack {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                            Text(URL(fileURLWithPath: imagePath).lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // File path
                    Text("Path: \(imagePath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            
            // Picker buttons
            HStack(spacing: 12) {
                if #available(iOS 16.0, *) {
                    PhotosPickerWrapper(
                        onPhotoSelected: { photoItem in
                            Task {
                                await loadSelectedPhoto(photoItem)
                            }
                        }
                    )
                } else {
                    Button(action: {
                        errorInfo = "Photo picker requires iOS 16.0 or later. Please use the Files option instead."
                        errorShow = true
                    }) {
                        Label("Photos (iOS 16+)", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
                
                Button(action: {
                    showingFilePicker = true
                }) {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            // Manual path entry
            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Path to image file", text: $imagePath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: imagePath) { newPath in
                        loadImagePreview(from: newPath)
                    }
            }
            
            // Video transformations for image-generated videos
            if !imagePath.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Transformations")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("Image will be converted to video and can be transformed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    // Verified Mode toggle
                    HStack {
                        Toggle("Verified Mode", isOn: Binding(
                            get: { spoofCameraMode == "verified" },
                            set: { newValue in
                                spoofCameraMode = newValue ? "verified" : "standard"
                                Task {
                                    await processImageToVideoTransforms()
                                }
                            }
                        ))
                        
                        Spacer()
                        
                        if spoofCameraMode == "verified" {
                            Label("Anti-Detection", systemImage: "checkmark.shield")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.bottom, 4)
                    
                    if spoofCameraMode == "verified" {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Adds Nomix-style random variations to avoid detection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // Standard transformation controls
                    Picker("Orientation", selection: Binding(
                        get: { spoofCameraTransformOrientation },
                        set: { newValue in
                            spoofCameraTransformOrientation = newValue
                            Task {
                                await processImageToVideoTransforms()
                            }
                        }
                    )) {
                        Text("Original").tag("none")
                        Text("Force Portrait").tag("portrait") 
                        Text("Force Landscape").tag("landscape")
                        Text("Rotate 90°").tag("rotate90")
                        Text("Rotate 180°").tag("rotate180")
                        Text("Rotate 270°").tag("rotate270")
                    }
                    
                    Picker("Scale", selection: Binding(
                        get: { spoofCameraTransformScale },
                        set: { newValue in
                            spoofCameraTransformScale = newValue
                            Task {
                                await processImageToVideoTransforms()
                            }
                        }
                    )) {
                        Text("Fit").tag("fit")
                        Text("Fill").tag("fill")
                        Text("Stretch").tag("stretch")
                    }
                    
                    Picker("Flip", selection: Binding(
                        get: { spoofCameraTransformFlip },
                        set: { newValue in
                            spoofCameraTransformFlip = newValue
                            Task {
                                await processImageToVideoTransforms()
                            }
                        }
                    )) {
                        Text("None").tag("none")
                        Text("Horizontal").tag("horizontal")
                        Text("Vertical").tag("vertical")
                        Text("Both").tag("both")
                    }
                    
                    // Processing indicator
                    if isProcessingVideo {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Converting image to video with transformations...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            ProgressView(value: videoProcessingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            
                            Text("\(Int(videoProcessingProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    
                    // Transform summary
                    if hasAnyImageTransforms() {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Transformations:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                if spoofCameraMode == "verified" {
                                    Label("Verified", systemImage: "checkmark.shield")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                                
                                if spoofCameraTransformOrientation != "none" {
                                    Label(orientationLabel(), systemImage: "rotate.3d")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                
                                if spoofCameraTransformFlip != "none" {
                                    Label(spoofCameraTransformFlip.capitalized, systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                }
                                
                                if spoofCameraTransformScale != "fit" {
                                    Label(spoofCameraTransformScale.capitalized, systemImage: "viewfinder")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    Text("Image will be converted to a looping video with applied transformations. Verified mode adds anti-detection variations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .onAppear {
            if !imagePath.isEmpty {
                loadImagePreview(from: imagePath)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }
    
    // MARK: - Helper Functions
    
    private func clearImage() {
        if FileManager.default.fileExists(atPath: imagePath) {
            do {
                try FileManager.default.removeItem(atPath: imagePath)
            } catch {
                errorInfo = "Failed to remove image file: \(error.localizedDescription)"
                errorShow = true
            }
        }
        imagePath = ""
        previewImage = nil
    }
    
    private func hasAnyImageTransforms() -> Bool {
        return spoofCameraMode == "verified" ||
               spoofCameraTransformOrientation != "none" ||
               spoofCameraTransformFlip != "none" ||
               spoofCameraTransformScale != "fit"
    }
    
    private func orientationLabel() -> String {
        switch spoofCameraTransformOrientation {
        case "portrait": return "Portrait"
        case "landscape": return "Landscape"
        case "rotate90": return "90°"
        case "rotate180": return "180°"
        case "rotate270": return "270°"
        default: return "Original"
        }
    }
    
    private func loadImagePreview(from path: String) {
        guard !path.isEmpty else {
            previewImage = nil
            return
        }
        
        guard FileManager.default.fileExists(atPath: path) else {
            previewImage = nil
            DispatchQueue.main.async {
                errorInfo = "Image file not found at path: \(path)"
                errorShow = true
            }
            return
        }
        
        // Load image asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = UIImage(contentsOfFile: path) {
                DispatchQueue.main.async {
                    previewImage = image
                }
            } else {
                DispatchQueue.main.async {
                    previewImage = nil
                    errorInfo = "Failed to load image from file. File may be corrupted or not a valid image format."
                    errorShow = true
                }
            }
        }
    }
    
    @available(iOS 16.0, *)
    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // Validate that this is actually image data
                guard UIImage(data: data) != nil else {
                    await MainActor.run {
                        errorInfo = "Selected file is not a valid image format"
                        errorShow = true
                    }
                    return
                }
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraImagesFolder = documentsPath.appendingPathComponent("CameraSpoof/Images")
                
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: cameraImagesFolder, withIntermediateDirectories: true)
                
                // Generate unique filename with proper extension
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "camera_image_\(timestamp).jpg"
                let filePath = cameraImagesFolder.appendingPathComponent(fileName)
                
                // Save the image as JPEG for consistent format
                if let image = UIImage(data: data),
                   let jpegData = image.jpegData(compressionQuality: 0.9) {
                    try jpegData.write(to: filePath)
                    
                    await MainActor.run {
                        imagePath = filePath.path
                        previewImage = image
                    }
                } else {
                    throw NSError(domain: "ImageProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image data"])
                }
            }
        } catch {
            await MainActor.run {
                errorInfo = "Failed to import image: \(error.localizedDescription)"
                errorShow = true
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                errorInfo = "Unable to access selected file"
                errorShow = true
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                // First, validate it's an image
                guard let image = UIImage(contentsOfFile: url.path) else {
                    errorInfo = "Selected file is not a valid image format"
                    errorShow = true
                    return
                }
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraImagesFolder = documentsPath.appendingPathComponent("CameraSpoof/Images")
                
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: cameraImagesFolder, withIntermediateDirectories: true)
                
                // Use original filename but ensure unique
                let originalName = url.deletingPathExtension().lastPathComponent
                let extensionName = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "\(originalName)_\(timestamp).\(extensionName)"
                let destinationPath = cameraImagesFolder.appendingPathComponent(fileName)
                
                // Copy file to documents
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    try FileManager.default.removeItem(at: destinationPath)
                }
                try FileManager.default.copyItem(at: url, to: destinationPath)
                
                imagePath = destinationPath.path
                previewImage = image
                
            } catch {
                errorInfo = "Failed to import image file: \(error.localizedDescription)"
                errorShow = true
            }
            
        case .failure(let error):
            errorInfo = "File selection failed: \(error.localizedDescription)"
            errorShow = true
        }
    }
    
    @MainActor
    private func processImageToVideoTransforms() async {
        guard !imagePath.isEmpty else { return }
        
        let hasTransforms = hasAnyImageTransforms()
        guard hasTransforms else { return }
        
        isProcessingVideo = true
        videoProcessingProgress = 0.0
        
        do {
            // Load the image
            guard let sourceImage = UIImage(contentsOfFile: imagePath) else {
                throw NSError(domain: "ImageTransform", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
            }
            
            // Create video from image with transformations
            let transformedVideoPath = try await createVideoFromImageWithTransforms(
                sourceImage: sourceImage,
                orientation: spoofCameraTransformOrientation,
                scale: spoofCameraTransformScale,
                flip: spoofCameraTransformFlip,
                isVerifiedMode: spoofCameraMode == "verified"
            )
            
            // The video path is handled by the AVFoundation system
            print("✅ Image converted to video with transformations: \(transformedVideoPath)")
            
        } catch {
            errorInfo = "Image transformation failed: \(error.localizedDescription)"
            errorShow = true
        }
        
        isProcessingVideo = false
    }
    
    private func createVideoFromImageWithTransforms(
        sourceImage: UIImage,
        orientation: String,
        scale: String,
        flip: String,
        isVerifiedMode: Bool
    ) async throws -> String {
        
        // Create temporary video file
        let tempDir = NSTemporaryDirectory()
        let tempVideoPath = tempDir.appending("lc_image_transformed_video.mp4")
        
        // Remove existing temp file
        if FileManager.default.fileExists(atPath: tempVideoPath) {
            try FileManager.default.removeItem(atPath: tempVideoPath)
        }
        
        let outputURL = URL(fileURLWithPath: tempVideoPath)
        
        // Apply image transformations first
        let transformedImage = applyImageTransforms(
            image: sourceImage,
            orientation: orientation,
            scale: scale,
            flip: flip,
            isVerifiedMode: isVerifiedMode
        )
        
        // Create video writer
        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(transformedImage.size.width),
            AVVideoHeightKey: Int(transformedImage.size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1000000
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "imageToVideo")
            let input = writerInput
            let pixelAdaptor = adaptor
            let videoWriter = writer
            
            input.requestMediaDataWhenReady(on: queue) {
                let videoDuration: Double = 2.0 // 2 second loop
                let totalFrames = Int(videoDuration * 30)
                
                for frameNumber in 0..<totalFrames {
                    while !input.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                    
                    let frameTime = CMTime(value: Int64(frameNumber), timescale: 30)
                    
                    if let pixelBuffer = self.createPixelBuffer(from: transformedImage, frameNumber: frameNumber, isVerifiedMode: isVerifiedMode) {
                        pixelAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
                    }
                    
                    DispatchQueue.main.async {
                        self.videoProcessingProgress = Double(frameNumber) / Double(totalFrames)
                    }
                }
                
                input.markAsFinished()
                videoWriter.finishWriting {
                    if videoWriter.status == .completed {
                        continuation.resume(returning: tempVideoPath)
                    } else {
                        continuation.resume(throwing: videoWriter.error ?? NSError(domain: "VideoCreation", code: 1, userInfo: nil))
                    }
                }
            }
        }
    }
    
    private func applyImageTransforms(
        image: UIImage,
        orientation: String,
        scale: String,
        flip: String,
        isVerifiedMode: Bool
    ) -> UIImage {
        
        let targetSize = CGSize(width: 1080, height: 1920) // Default portrait
        
        // Apply orientation
        var transform = CGAffineTransform.identity
        var renderSize = targetSize
        
        switch orientation {
        case "landscape":
            renderSize = CGSize(width: targetSize.height, height: targetSize.width)
        case "rotate90":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
        case "rotate180":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi))
        case "rotate270":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
        default:
            break
        }
        
        // Apply flip
        switch flip {
        case "horizontal":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1))
        case "vertical":
            transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        case "both":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: -1))
        default:
            break
        }
        
        // Apply verified mode variations if enabled
        if isVerifiedMode {
            let seed = Int(Date().timeIntervalSince1970) % 1000
            var rng = SeededRandomGenerator(seed: seed)
            
            // Slight rotation variation
            let rotationVariation = rng.nextDouble(-0.5, 0.5) * .pi / 180.0
            transform = transform.concatenating(CGAffineTransform(rotationAngle: rotationVariation))
            
            // Slight scale variation
            let scaleVariation = rng.nextDouble(0.98, 1.02)
            transform = transform.concatenating(CGAffineTransform(scaleX: scaleVariation, y: scaleVariation))
        }
        
        // Apply transforms and return modified image
        UIGraphicsBeginImageContextWithOptions(renderSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        // Apply transform around center
        context.translateBy(x: renderSize.width / 2, y: renderSize.height / 2)
        context.concatenate(transform)
        context.translateBy(x: -renderSize.width / 2, y: -renderSize.height / 2)
        
        // Draw the image
        image.draw(in: CGRect(origin: .zero, size: renderSize))
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    private func createPixelBuffer(from image: UIImage, frameNumber: Int, isVerifiedMode: Bool) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(image.size.width),
            Int(image.size.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(image.size.width),
            height: Int(image.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        
        // Add verified mode subtle variations per frame
        if isVerifiedMode && frameNumber % 10 == 0 {
            let variation = Float(frameNumber % 100) / 1000.0 // Very subtle brightness variation
            context.setAlpha(CGFloat(1.0 + variation))
        }
        
        context.draw(image.cgImage!, in: CGRect(origin: .zero, size: image.size))
        
        return buffer
    }
}

struct CameraVideoPickerView: View {
    @Binding var videoPath: String
    @Binding var loopVideo: Bool
    @Binding var errorInfo: String
    @Binding var errorShow: Bool
    
    @State private var showingFilePicker = false
    @State private var videoThumbnail: UIImage?
    @State private var videoDuration: String = ""
    @State private var showingVideoPlayer = false // Add this for preview
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current video display
            if !videoPath.isEmpty {
                HStack {
                    Text("Current Video:")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        // Remove the file from filesystem before clearing the path
                        if FileManager.default.fileExists(atPath: videoPath) {
                            do {
                                try FileManager.default.removeItem(atPath: videoPath)
                            } catch {
                                errorInfo = "Failed to remove video file: \(error.localizedDescription)"
                                errorShow = true
                            }
                        }
                        videoPath = ""
                        videoThumbnail = nil
                        videoDuration = ""
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                
                if let videoThumbnail = videoThumbnail {
                    Button(action: {
                        showingVideoPlayer = true
                    }) {
                        ZStack {
                            Image(uiImage: videoThumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 120)
                                .cornerRadius(8)
                            
                            // Play button overlay
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 50, height: 50)
                                
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if !videoDuration.isEmpty {
                                Text(videoDuration)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        
                        Spacer()
                        
                        // Show if this is a transformed video
                        if videoPath.contains("_transformed") {
                            Label("Transformed", systemImage: "wand.and.rays")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "video")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: videoPath).lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Preview Video") {
                                showingVideoPlayer = true
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Text("Path: \(videoPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            
            // Video settings
            if !videoPath.isEmpty {
                Toggle("Loop Video", isOn: $loopVideo)
            }
            
            // Picker buttons - FIXED VERSION
            HStack(spacing: 12) {
                if #available(iOS 16.0, *) {
                    VideoPickerWrapper(
                        onVideoSelected: { videoItem in
                            Task {
                                await loadSelectedVideo(videoItem)
                            }
                        }
                    )
                } else {
                    Button(action: {
                        errorInfo = "Photo picker requires iOS 16.0 or later. Please use the Files option instead."
                        errorShow = true
                    }) {
                        Label("Photos (iOS 16+)", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
                
                Button(action: {
                    showingFilePicker = true
                }) {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            // Manual path entry
            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Path to video file", text: $videoPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: videoPath) { newPath in
                        loadVideoPreview(from: newPath)
                    }
            }
        }
        .onAppear {
            if !videoPath.isEmpty {
                loadVideoPreview(from: videoPath)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .video],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if !videoPath.isEmpty {
                VideoPlayerView(videoPath: videoPath, isPresented: $showingVideoPlayer)
            }
        }
    }
    
    @available(iOS 16.0, *)
    private func loadSelectedVideo(_ item: PhotosPickerItem) async {
        do {
            if let movieData = try await item.loadTransferable(type: Data.self) {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraVideosFolder = documentsPath.appendingPathComponent("CameraSpoof/Videos")
                
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: cameraVideosFolder, withIntermediateDirectories: true)
                
                // Generate unique filename
                let fileName = "camera_video_\(Date().timeIntervalSince1970).mp4"
                let filePath = cameraVideosFolder.appendingPathComponent(fileName)
                
                // Save the video
                try movieData.write(to: filePath)
                
                await MainActor.run {
                    videoPath = filePath.path
                    loadVideoPreview(from: videoPath)
                }
            }
        } catch {
            await MainActor.run {
                errorInfo = "Failed to import video: \(error.localizedDescription)"
                errorShow = true
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraVideosFolder = documentsPath.appendingPathComponent("CameraSpoof/Videos")
                
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: cameraVideosFolder, withIntermediateDirectories: true)
                
                let fileName = url.lastPathComponent
                let destinationPath = cameraVideosFolder.appendingPathComponent(fileName)
                
                // Copy file to documents
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    try FileManager.default.removeItem(at: destinationPath)
                }
                try FileManager.default.copyItem(at: url, to: destinationPath)
                
                videoPath = destinationPath.path
                loadVideoPreview(from: videoPath)
                
            } catch {
                errorInfo = "Failed to import video file: \(error.localizedDescription)"
                errorShow = true
            }
            
        case .failure(let error):
            errorInfo = "File selection failed: \(error.localizedDescription)"
            errorShow = true
        }
    }
    
    private func loadVideoPreview(from path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            videoThumbnail = nil
            videoDuration = ""
            return
        }
        
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        
        // Generate thumbnail
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 300, height: 300) // Add size limit for better performance
        
        Task {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: CMTime.zero, actualTime: nil)
                await MainActor.run {
                    videoThumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                await MainActor.run {
                    videoThumbnail = nil
                }
            }
            
            // Get comprehensive video information
            do {
                // Get duration
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                
                // Get video track information
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                
                var videoInfo = ""
                
                if let videoTrack = videoTracks.first {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let preferredTransform = try await videoTrack.load(.preferredTransform)
                    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                    
                    // Calculate actual display size after transformation
                    let displaySize = naturalSize.applying(preferredTransform)
                    let actualWidth = abs(displaySize.width)
                    let actualHeight = abs(displaySize.height)
                    
                    // Determine video orientation
                    let isRotated = preferredTransform.b != 0 || preferredTransform.c != 0
                    let orientation = isRotated ? "Rotated" : "Normal"
                    
                    // Get file size
                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: path)
                    let fileSize = fileAttributes[.size] as? Int64 ?? 0
                    let fileSizeMB = Double(fileSize) / (1024 * 1024)
                    
                    // Build info string
                    videoInfo = String(format: "%.1fs", seconds)
                    videoInfo += "\n\(Int(actualWidth))×\(Int(actualHeight))"
                    videoInfo += " (\(orientation))"
                    videoInfo += String(format: "\n%.1f fps", nominalFrameRate)
                    videoInfo += String(format: "\n%.1f MB", fileSizeMB)
                    
                    // Add codec information if available
                    if let formatDescriptions = try? await videoTrack.load(.formatDescriptions) {
                        for formatDescription in formatDescriptions {
                            let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
                            let codecString = fourCharCodeToString(codecType)
                            videoInfo += "\n\(codecString)"
                            break // Just show the first codec
                        }
                    }
                    
                    // Add audio info if available
                    if !audioTracks.isEmpty {
                        videoInfo += "\n🎵 Audio"
                    } else {
                        videoInfo += "\n🔇 No Audio"
                    }
                    
                    // Add transform info if video is transformed
                    if path.contains("_transformed") {
                        videoInfo += "\n✨ Processed"
                    }
                    
                } else {
                    videoInfo = String(format: "%.1fs", seconds)
                    videoInfo += "\nNo video track"
                }
                
                await MainActor.run {
                    videoDuration = videoInfo
                }
                
            } catch {
                await MainActor.run {
                    videoDuration = "Error loading info"
                }
            }
        }
    }

    // Helper function to convert FourCharCode to readable string
    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        
        // Try to create a readable string
        if let string = String(bytes: bytes, encoding: .ascii) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fallback to common codec names
        switch code {
        case 1635148593: return "H.264" // 'avc1'
        case 1752589105: return "H.264" // 'hvc1' 
        case 1211250227: return "H.265" // 'hev1'
        case 1129727304: return "ProRes" // 'ap4h'
        default: return "Unknown"
        }
    }
}

@available(iOS 16.0, *)
struct PhotosPickerWrapper: View {
    let onPhotoSelected: (PhotosPickerItem) -> Void
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images
        ) {
            Label("Photos", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .onChange(of: selectedItem) { newItem in
            if let item = newItem {
                onPhotoSelected(item)
                selectedItem = nil // Reset selection
            }
        }
    }
}

@available(iOS 16.0, *)
struct VideoPickerWrapper: View {
    let onVideoSelected: (PhotosPickerItem) -> Void
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .videos
        ) {
            Label("Photos", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .onChange(of: selectedItem) { newItem in
            if let item = newItem {
                onVideoSelected(item)
                selectedItem = nil // Reset selection
            }
        }
    }
}

struct VideoPlayerView: View {
    let videoPath: String
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            Group {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    VStack {
                        ProgressView("Loading video...")
                        Text(URL(fileURLWithPath: videoPath).lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                }
            }
            .navigationTitle("Video Preview")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") {
                    player?.pause()
                    isPresented = false
                }
            )
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        guard FileManager.default.fileExists(atPath: videoPath) else {
            return
        }
        
        let url = URL(fileURLWithPath: videoPath)
        player = AVPlayer(url: url)
        
        // Set up looping if needed
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}