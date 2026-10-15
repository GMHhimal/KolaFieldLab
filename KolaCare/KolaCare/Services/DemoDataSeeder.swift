//
//  DemoDataSeeder.swift
//  KolaCare
//
//  Creates a realistic demo garden (four plots near Dambulla, Sri Lanka's
//  vegetable hub) with several weeks of scan history, so every screen and
//  chart can be demonstrated immediately — including in the Simulator.
//

import Foundation
import SwiftData
import UIKit

@MainActor
enum DemoDataSeeder {
    private struct DemoScan {
        let daysAgo: Int
        let diseaseID: String
        let affected: Double
        let sample: String
        let steps: [Int]
    }

    private struct DemoPlant {
        let name: String
        let crop: Crop
        let plot: String
        let latitude: Double
        let longitude: Double
        let scans: [DemoScan]
    }

    private static let plants: [DemoPlant] = [
        DemoPlant(name: "Tomato bed A", crop: .tomato, plot: "Home garden", latitude: 7.8742, longitude: 80.6511, scans: [
            DemoScan(daysAgo: 21, diseaseID: "tomato.healthy", affected: 0.01, sample: "SampleLeafHealthy", steps: []),
            DemoScan(daysAgo: 14, diseaseID: "tomato.early_blight", affected: 0.12, sample: "SampleLeafSpotted", steps: [0]),
            DemoScan(daysAgo: 7, diseaseID: "tomato.early_blight", affected: 0.26, sample: "SampleLeafSpotted", steps: [0, 1]),
            DemoScan(daysAgo: 1, diseaseID: "tomato.early_blight", affected: 0.09, sample: "SampleLeafSpotted", steps: [0, 1, 2])
        ]),
        DemoPlant(name: "Chilli row 2", crop: .chilli, plot: "Upper terrace", latitude: 7.8761, longitude: 80.6535, scans: [
            DemoScan(daysAgo: 18, diseaseID: "chilli.healthy", affected: 0.02, sample: "SampleLeafHealthy", steps: []),
            DemoScan(daysAgo: 4, diseaseID: "chilli.bacterial_spot", affected: 0.38, sample: "SampleLeafSpotted", steps: [])
        ]),
        DemoPlant(name: "Potato plot", crop: .potato, plot: "Lower field", latitude: 7.8718, longitude: 80.6489, scans: [
            DemoScan(daysAgo: 10, diseaseID: "general.chlorosis", affected: 0.17, sample: "SampleLeafYellowing", steps: [0]),
            DemoScan(daysAgo: 2, diseaseID: "potato.healthy", affected: 0.03, sample: "SampleLeafHealthy", steps: [])
        ]),
        DemoPlant(name: "Paddy — Yala", crop: .rice, plot: "Paddy field", latitude: 7.8695, longitude: 80.6552, scans: [
            DemoScan(daysAgo: 6, diseaseID: "rice.healthy", affected: 0.02, sample: "SampleLeafHealthy", steps: [])
        ])
    ]

    static func seed(into context: ModelContext, now: Date = .now) {
        var thumbnails: [String: (Data?, Data?)] = [:]
        for name in ["SampleLeafHealthy", "SampleLeafSpotted", "SampleLeafYellowing"] {
            if let image = UIImage(named: name)?.cgImage {
                thumbnails[name] = ImageProcessing.prepareForStorage(image)
            }
        }

        for demo in plants {
            let plant = Plant(name: demo.name, crop: demo.crop, plotName: demo.plot,
                              plantedOn: Calendar.current.date(byAdding: .day, value: -45, to: now),
                              createdAt: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now)
            plant.latitude = demo.latitude
            plant.longitude = demo.longitude
            context.insert(plant)

            for scan in demo.scans {
                let images = thumbnails[scan.sample]
                let record = ScanRecord(
                    date: Calendar.current.date(byAdding: .day, value: -scan.daysAgo, to: now) ?? now,
                    imageData: images?.0,
                    thumbnailData: images?.1,
                    diseaseID: scan.diseaseID,
                    confidence: scan.diseaseID.hasPrefix("general") ? 0.7 : 0.91,
                    affectedArea: scan.affected,
                    chlorosisFraction: scan.affected * 0.4,
                    necrosisFraction: scan.affected * 0.6,
                    healthScore: scan.diseaseID.hasSuffix("healthy")
                        ? max(92, HealthScore.from(affectedArea: scan.affected))
                        : HealthScore.from(affectedArea: scan.affected),
                    engine: scan.diseaseID.hasPrefix("general") ? .colourAnalysis : .coreML,
                    completedSteps: scan.steps)
                context.insert(record)
                record.plant = plant
            }
        }
        try? context.save()
    }
}
