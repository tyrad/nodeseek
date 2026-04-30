//
//  NodeSeekSplashVector.swift
//  nodeseek
//

import UIKit

enum NodeSeekSplashVector {
    static let canvasSize = CGSize(width: 1024, height: 1024)
    static let accentColor = UIColor(red: 0x18 / 255.0, green: 0xB3 / 255.0, blue: 0xB0 / 255.0, alpha: 1)
    static let logoBounds = CGRect(x: 176, y: 273, width: 729, height: 451)
    static let dotBounds = CGRect(x: 822, y: 664, width: 83, height: 60)

    static func backgroundColor(for traitCollection: UITraitCollection) -> UIColor {
        traitCollection.userInterfaceStyle == .dark ? .black : .white
    }

    static func wordmarkColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return .white
        }
        return UIColor(red: 0x1A / 255.0, green: 0x1F / 255.0, blue: 0x24 / 255.0, alpha: 1)
    }

    static func lightSweepColor(for traitCollection: UITraitCollection) -> UIColor {
        traitCollection.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.45)
            : UIColor.white.withAlphaComponent(0.62)
    }

    static func accentPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 904, y: 665))
        path.addLine(to: CGPoint(x: 860, y: 664))
        path.addLine(to: CGPoint(x: 822, y: 723))
        path.addLine(to: CGPoint(x: 865, y: 723))
        path.closeSubpath()
        return path
    }

    static func nBodyPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 176, y: 274))
        path.addLine(to: CGPoint(x: 177, y: 723))
        path.addLine(to: CGPoint(x: 271, y: 722))
        path.addLine(to: CGPoint(x: 274, y: 452))
        path.addLine(to: CGPoint(x: 442, y: 723))
        path.addLine(to: CGPoint(x: 503, y: 634))
        path.addLine(to: CGPoint(x: 271, y: 273))
        path.closeSubpath()
        return path
    }

    static func nFinalStrokePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 417, y: 274))
        path.addLine(to: CGPoint(x: 416, y: 459))
        path.addLine(to: CGPoint(x: 506, y: 600))
        path.addLine(to: CGPoint(x: 508, y: 463))
        path.addLine(to: CGPoint(x: 507, y: 273))
        path.closeSubpath()
        return path
    }

    static func sBodyPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 442, y: 723))
        path.addLine(to: CGPoint(x: 742, y: 722))
        path.addLine(to: CGPoint(x: 772, y: 714))
        path.addLine(to: CGPoint(x: 797, y: 700))
        path.addLine(to: CGPoint(x: 818, y: 680))
        path.addLine(to: CGPoint(x: 833, y: 658))
        path.addLine(to: CGPoint(x: 842, y: 638))
        path.addLine(to: CGPoint(x: 848, y: 616))
        path.addLine(to: CGPoint(x: 850, y: 566))
        path.addLine(to: CGPoint(x: 841, y: 525))
        path.addLine(to: CGPoint(x: 832, y: 506))
        path.addLine(to: CGPoint(x: 820, y: 489))
        path.addLine(to: CGPoint(x: 793, y: 466))
        path.addLine(to: CGPoint(x: 764, y: 453))
        path.addLine(to: CGPoint(x: 737, y: 448))
        path.addLine(to: CGPoint(x: 662, y: 448))
        path.addLine(to: CGPoint(x: 650, y: 445))
        path.addLine(to: CGPoint(x: 638, y: 438))
        path.addLine(to: CGPoint(x: 628, y: 426))
        path.addLine(to: CGPoint(x: 624, y: 415))
        path.addLine(to: CGPoint(x: 623, y: 401))
        path.addLine(to: CGPoint(x: 627, y: 387))
        path.addLine(to: CGPoint(x: 633, y: 378))
        path.addLine(to: CGPoint(x: 642, y: 370))
        path.addLine(to: CGPoint(x: 657, y: 364))
        path.addLine(to: CGPoint(x: 790, y: 364))
        path.addLine(to: CGPoint(x: 847, y: 274))
        path.addLine(to: CGPoint(x: 652, y: 273))
        path.addLine(to: CGPoint(x: 625, y: 277))
        path.addLine(to: CGPoint(x: 596, y: 288))
        path.addLine(to: CGPoint(x: 576, y: 302))
        path.addLine(to: CGPoint(x: 558, y: 322))
        path.addLine(to: CGPoint(x: 543, y: 349))
        path.addLine(to: CGPoint(x: 536, y: 372))
        path.addLine(to: CGPoint(x: 533, y: 393))
        path.addLine(to: CGPoint(x: 535, y: 435))
        path.addLine(to: CGPoint(x: 541, y: 457))
        path.addLine(to: CGPoint(x: 550, y: 476))
        path.addLine(to: CGPoint(x: 562, y: 493))
        path.addLine(to: CGPoint(x: 576, y: 507))
        path.addLine(to: CGPoint(x: 604, y: 525))
        path.addLine(to: CGPoint(x: 631, y: 534))
        path.addLine(to: CGPoint(x: 653, y: 537))
        path.addLine(to: CGPoint(x: 729, y: 538))
        path.addLine(to: CGPoint(x: 746, y: 547))
        path.addLine(to: CGPoint(x: 756, y: 559))
        path.addLine(to: CGPoint(x: 761, y: 570))
        path.addLine(to: CGPoint(x: 763, y: 582))
        path.addLine(to: CGPoint(x: 760, y: 604))
        path.addLine(to: CGPoint(x: 753, y: 617))
        path.addLine(to: CGPoint(x: 744, y: 626))
        path.addLine(to: CGPoint(x: 726, y: 634))
        path.addLine(to: CGPoint(x: 503, y: 634))
        path.closeSubpath()
        return path
    }

    static func nLeftStrokeRevealPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 224, y: 720))
        path.addLine(to: CGPoint(x: 224, y: 274))
        return path
    }

    static func nDiagonalStrokeRevealPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 224, y: 274))
        path.addLine(to: CGPoint(x: 496, y: 720))
        return path
    }

    static func nFinalStrokeRevealPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 462, y: 274))
        path.addLine(to: CGPoint(x: 462, y: 720))
        return path
    }

    static func sStrokeRevealPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 825, y: 318))
        path.addLine(to: CGPoint(x: 656, y: 318))
        path.addCurve(
            to: CGPoint(x: 580, y: 410),
            control1: CGPoint(x: 598, y: 318),
            control2: CGPoint(x: 570, y: 350)
        )
        path.addCurve(
            to: CGPoint(x: 666, y: 492),
            control1: CGPoint(x: 590, y: 470),
            control2: CGPoint(x: 618, y: 492)
        )
        path.addLine(to: CGPoint(x: 736, y: 492))
        path.addCurve(
            to: CGPoint(x: 809, y: 582),
            control1: CGPoint(x: 786, y: 492),
            control2: CGPoint(x: 809, y: 528)
        )
        path.addCurve(
            to: CGPoint(x: 724, y: 679),
            control1: CGPoint(x: 809, y: 642),
            control2: CGPoint(x: 774, y: 679)
        )
        path.addLine(to: CGPoint(x: 504, y: 679))
        path.addLine(to: CGPoint(x: 430, y: 679))
        return path
    }
}
