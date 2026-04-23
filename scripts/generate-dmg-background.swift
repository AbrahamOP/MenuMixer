#!/usr/bin/env swift
// Génère l'image de fond du DMG.
// Usage : swift scripts/generate-dmg-background.swift [chemin-sortie.png]
// Par défaut : Resources/dmg-background.png

import AppKit
import Foundation

let width: CGFloat = 600
let height: CGFloat = 400
let size = NSSize(width: width, height: height)

// Positions (doivent correspondre aux --icon et --app-drop-link dans create-dmg.sh)
let iconY: CGFloat = 220
let appIconX: CGFloat = 160
let applicationsIconX: CGFloat = 440

let image = NSImage(size: size)
image.lockFocus()

// Fond : dégradé bleu nuit vers noir
if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.18, alpha: 1.0),
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.09, alpha: 1.0)
]) {
    gradient.draw(in: NSRect(origin: .zero, size: size), angle: 270)
}

// Halo bleuté derrière le titre
if let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.95, alpha: 0.22),
    NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.95, alpha: 0.00)
]) {
    let glowRect = NSRect(x: width/2 - 180, y: height - 170, width: 360, height: 150)
    glow.draw(in: glowRect, relativeCenterPosition: .zero)
}

// Titre
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
    .foregroundColor: NSColor.white,
    .kern: -0.5
]
let title = NSAttributedString(string: "MenuMixer", attributes: titleAttrs)
let titleSize = title.size()
title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 75))

// Sous-titre
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.55)
]
let subtitle = NSAttributedString(
    string: "Mélangeur audio par application — macOS",
    attributes: subtitleAttrs
)
let subSize = subtitle.size()
subtitle.draw(at: NSPoint(x: (width - subSize.width) / 2, y: height - 100))

// Flèche stylisée entre les deux icônes
let arrowMidX = (appIconX + applicationsIconX) / 2
let arrowY: CGFloat = iconY + 20
let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: arrowMidX - 50, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowMidX + 50, y: arrowY))
// Tête de flèche
arrowPath.move(to: NSPoint(x: arrowMidX + 50, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowMidX + 38, y: arrowY + 12))
arrowPath.move(to: NSPoint(x: arrowMidX + 50, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowMidX + 38, y: arrowY - 12))

NSColor.white.withAlphaComponent(0.35).setStroke()
arrowPath.lineWidth = 2.5
arrowPath.lineCapStyle = .round
arrowPath.stroke()

// Labels sous les icônes (au cas où les vrais noms seraient masqués ou peu lisibles)
let captionAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.75)
]

// Instructions en bas (remontées pour être au-dessus de la status bar Finder)
let instrAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.60)
]
let instr = NSAttributedString(
    string: "Glisser MenuMixer vers Applications pour installer",
    attributes: instrAttrs
)
let instrSize = instr.size()
instr.draw(at: NSPoint(x: (width - instrSize.width) / 2, y: 75))

image.unlockFocus()

// Sauvegarde en PNG
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/dmg-background.png"
let outputURL = URL(fileURLWithPath: outputPath)

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Erreur génération PNG\n".data(using: .utf8)!)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)

print("Généré : \(outputURL.path) (\(Int(width))×\(Int(height)))")
