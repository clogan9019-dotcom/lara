//
//  LocationSpooferView.swift
//  lara
//

import SwiftUI
import UIKit

struct LocationSpooferView: View {
    @ObservedObject var mgr: laramgr

    @AppStorage("lara.locationspoofer.latitude") private var savedLatitude: Double = 37.3349
    @AppStorage("lara.locationspoofer.longitude") private var savedLongitude: Double = -122.0090
    @AppStorage("lara.locationspoofer.altitude") private var savedAltitude: Double = 0
    @AppStorage("lara.locationspoofer.accuracy") private var savedAccuracy: Double = 5
    @AppStorage("lara.locationspoofer.active") private var simulationActive: Bool = false

    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @State private var altitudeText: String = ""
    @State private var accuracy: Double = 5
    @State private var isWorking: Bool = false
    @State private var isRestoring: Bool = false
    @State private var lastResult: String? = nil

    var body: some View {
        List {
            if !mgr.dsready {
                Section(header: HeaderLabel(text: "Status", icon: "exclamationmark.triangle.fill")) {
                    Text("Kernel R/W is not ready. Run the exploit from the home tab first.")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: HeaderLabel(text: "Status", icon: "location.fill")) {
                HStack {
                    Text("Location Simulation")
                    Spacer()
                    Text(simulationActive ? "Active" : "Inactive")
                        .foregroundColor(simulationActive ? .green : .secondary)
                        .monospaced()
                }
                if simulationActive {
                    HStack {
                        Text("Target")
                        Spacer()
                        Text(String(format: "%.5f, %.5f", savedLatitude, savedLongitude))
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                }
            }

            Section(header: HeaderLabel(text: "Coordinate", icon: "mappin.and.ellipse")) {
                HStack {
                    Text("Latitude")
                    Spacer()
                    TextField("-90 to 90", text: $latitudeText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .monospaced()
                        .frame(maxWidth: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                HStack {
                    Text("Longitude")
                    Spacer()
                    TextField("-180 to 180", text: $longitudeText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .monospaced()
                        .frame(maxWidth: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                HStack {
                    Text("Altitude")
                    Spacer()
                    TextField("0", text: $altitudeText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .monospaced()
                        .frame(maxWidth: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Text("m")
                        .foregroundColor(.secondary)
                }
            }

            Section(
                header: HeaderLabel(text: "Options", icon: "slider.horizontal.3"),
                footer: Text("The simulated fix loops in a small radius around the target, derived from the accuracy value.")
            ) {
                HStack {
                    Text("Accuracy")
                    Spacer()
                    Text("\(Int(accuracy)) m")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                Slider(value: $accuracy, in: 1...100, step: 1)
            }

            Section(
                header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver"),
                footer: Text("Apple Maps is used as the host process and is launched automatically when it is not running. Keep lara open while applying. A reboot also clears the simulation. Simulated locations can affect time zone, weather, reminders and other location based services, so use this responsibly.")
            ) {
                Button {
                    applySimulation()
                } label: {
                    if isWorking && !isRestoring {
                        HStack {
                            Text("Applying…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Start Simulation")
                    }
                }
                .disabled(isWorking || !mgr.dsready)

                Button {
                    restoreLocation()
                } label: {
                    if isWorking && isRestoring {
                        HStack {
                            Text("Restoring…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Restore Real Location")
                    }
                }
                .disabled(isWorking || !mgr.dsready)
            }
        }
        .navigationTitle("Location Spoofer")
        .onAppear(perform: syncFields)
        .alert("Result", isPresented: .constant(lastResult != nil)) {
            Button("OK") { lastResult = nil }
        } message: {
            Text(lastResult ?? "")
        }
    }

    private func syncFields() {
        latitudeText = fieldText(savedLatitude, decimals: 7)
        longitudeText = fieldText(savedLongitude, decimals: 7)
        altitudeText = fieldText(savedAltitude, decimals: 1)
        accuracy = min(max(savedAccuracy, 1), 100)
    }

    private func fieldText(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
            .replacingOccurrences(of: ",", with: ".")
    }

    private func value(from text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private func applySimulation() {
        guard let latitude = value(from: latitudeText), latitude >= -90, latitude <= 90 else {
            lastResult = "Enter a latitude between -90 and 90."
            return
        }
        guard let longitude = value(from: longitudeText), longitude >= -180, longitude <= 180 else {
            lastResult = "Enter a longitude between -180 and 180."
            return
        }
        let altitude = value(from: altitudeText) ?? 0
        let targetAccuracy = min(max(accuracy, 1), 100)

        savedLatitude = latitude
        savedLongitude = longitude
        savedAltitude = altitude
        savedAccuracy = targetAccuracy

        run(restoring: false) {
            locationspoof_start(latitude, longitude, altitude, targetAccuracy)
        }
    }

    private func restoreLocation() {
        run(restoring: true) {
            locationspoof_stop()
        }
    }

    private func run(restoring: Bool, work: @escaping () -> Int32) {
        isWorking = true
        isRestoring = restoring
        globallogger.log(restoring ? "(locsim) restoring real location…" : "(locsim) applying simulated location…")

        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "LocationSpoofer") {
            if task != .invalid {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = work()
            DispatchQueue.main.async {
                if task != .invalid {
                    UIApplication.shared.endBackgroundTask(task)
                    task = .invalid
                }
                isWorking = false
                finish(result, restoring: restoring)
            }
        }
    }

    private func finish(_ result: Int32, restoring: Bool) {
        if result == LOCSIM_OK.rawValue {
            if restoring {
                simulationActive = false
                lastResult = "Real location restored. Some apps may need a moment, or a restart, to notice."
                globallogger.log("(locsim) simulation stopped")
            } else {
                simulationActive = true
                lastResult = String(
                    format: "Location simulation started at %.5f, %.5f.\n\nOpen Maps to confirm the spoofed fix. Restore the real location here, or reboot, to clear it.",
                    savedLatitude, savedLongitude
                )
                globallogger.log("(locsim) simulation started")
            }
        } else {
            lastResult = errormessage(result)
            globallogger.log("(locsim) failed with code \(result)")
        }
    }

    private func errormessage(_ code: Int32) -> String {
        switch code {
        case LOCSIM_ERR_KERNEL.rawValue:
            return "Kernel R/W is not ready. Run the exploit first."
        case LOCSIM_ERR_COORDINATES.rawValue:
            return "Those coordinates are not valid."
        case LOCSIM_ERR_NO_MAPS.rawValue:
            return "Apple Maps could not be launched. Make sure Maps is installed and set up, then try again."
        case LOCSIM_ERR_HOST.rawValue:
            return "Could not attach to Apple Maps. Bring lara back to the foreground and try again."
        case LOCSIM_ERR_MANAGER.rawValue:
            return "CoreLocation's simulation service is unavailable on this version."
        case LOCSIM_ERR_APPLY.rawValue:
            return "The simulated location was not accepted. Check the log for details."
        default:
            return "Something went wrong. Check the log for details."
        }
    }
}
