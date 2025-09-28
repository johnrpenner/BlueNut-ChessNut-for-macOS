//
//  BlueNutConnect.swift v1.0
//  BlueNut Connect ©2025 by John Roland Penner
//  Connects to a ChessNut Air via Bluetooth 
//
//  Created by John Roland Penner on 2025-09-28.
//

import Foundation
import CoreBluetooth
import Combine

class blueNutConnect: NSObject {
    
    // MARK: - Constants (translated from Python constants.py)
    private let deviceList = ["Chessnut Air", "Smart Chess"]
    
    private struct BtCharacteristics {
        static let write = CBUUID(string: "1B7E8272-2877-41C3-B46E-CF057C562023")
        static let readMiscData = CBUUID(string: "1B7E8273-2877-41C3-B46E-CF057C562023")
        static let readBoardData = CBUUID(string: "1B7E8262-2877-41C3-B46E-CF057C562023")
        static let readOtbData = CBUUID(string: "1B7E8283-2877-41C3-B46E-CF057C562023")
    }
    
    private struct BtCommands {
        static let initCode = Data([0x21, 0x01, 0x00])
        static let getBatteryStatus = Data([0x29, 0x01, 0x00])
        static let setLedsPrefix = Data([0x0A, 0x08])
    }
    
    private struct BtResponses {
        static let headBuffer = Data([0x01, 0x24])
        static let heartbeatCode = Data([0x23, 0x01, 0x00])
    }
    
    // Chess piece conversion dictionary
    private let convertDict: [UInt8: String] = [
        0: " ", 1: "q", 2: "k", 3: "b", 4: "p", 5: "n",
        6: "R", 7: "P", 8: "r", 9: "B", 10: "N", 11: "Q", 12: "K"
    ]
    
    // MARK: - Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var readBoardCharacteristic: CBCharacteristic?
    private var readMiscCharacteristic: CBCharacteristic?
    private var readOtbCharacteristic: CBCharacteristic?
    
    private var discoveredPeripherals: [CBPeripheral] = []
    private var boardState = Data(count: 32)
    private var isConnected = false
    private var lastUpdateTime: Date?
    
    // Callback to update UI
    var onScanResult: ((String) -> Void)?
    var onConnectionChange: ((Bool, String) -> Void)?
    var onBoardUpdate: ((String) -> Void)?
    var onRawBoardData: ((Data) -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    func startScanning() {
        discoveredPeripherals.removeAll()
        onScanResult?("Scanning for devices...")
        
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
            
            // Stop scanning after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                self.centralManager.stopScan()
                if self.discoveredPeripherals.isEmpty {
                    self.onScanResult?("No Chessnut Air devices found")
                }
            }
        } else {
            onScanResult?("Bluetooth is not powered on")
        }
    }
    
    func connectToDevice() {
        guard let peripheral = discoveredPeripherals.first else {
            onConnectionChange?(false, "No device found to connect")
            return
        }
        
        onConnectionChange?(false, "Connecting to \(peripheral.name ?? "Unknown")...")
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnectFromDevice() {
        guard let peripheral = connectedPeripheral else {
            onConnectionChange?(false, "No device to disconnect from")
            return
        }
        
        onConnectionChange?(false, "Disconnecting from \(peripheral.name ?? "Unknown")...")
        
        // Stop notifications first
        if let readBoardChar = readBoardCharacteristic {
            peripheral.setNotifyValue(false, for: readBoardChar)
        }
        if let readMiscChar = readMiscCharacteristic {
            peripheral.setNotifyValue(false, for: readMiscChar)
        }
        if let readOtbChar = readOtbCharacteristic {
            peripheral.setNotifyValue(false, for: readOtbChar)
        }
        
        // Disconnect from the peripheral
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func readBoardPosition() -> String {
        return boardStateAsASCII()
    }
    
    func getCurrentBoardData() -> Data {
        return boardState
    }
    
    func sendLEDTestPattern() {
        guard isConnected else {
            print("Not connected to device")
            return
        }
        
        let testPattern = createLEDTestPattern()
        runLEDAnimation(pattern: testPattern)
    }
    
    // MARK: - Private Methods
    private func boardStateAsASCII() -> String {
        var result = "  a b c d e f g h\n"
        
        for rank in (0..<8).reversed() {
            result += "\(rank + 1) "
            for file in 0..<8 {
                let square = rank * 8 + file
                let byteIndex = (63 - square) / 2
                let isLeft = (63 - square) % 2 == 0
                
                if byteIndex < boardState.count {
                    let byte = boardState[byteIndex]
                    let pieceValue = isLeft ? (byte & 0x0F) : (byte >> 4)
                    let piece = convertDict[pieceValue] ?? " "
                    result += "\(piece) "
                } else {
                    result += "  "
                }
            }
            result += "\(rank + 1)\n"
        }
        result += "  a b c d e f g h"
        return result
    }
    
    private func createLEDTestPattern() -> [[String]] {
        let phase0: [String] = [] // All LEDs OFF
        let phase1 = ["d4", "d5", "e4", "e5"]
        let phase2 = ["c3", "c4", "c5", "c6", "d6", "e6", "f6", "f5", "f4", "f3", "e3", "d3"]
        let phase3 = ["b2", "b3", "b4", "b5", "b6", "b7", "c7", "d7", "e7", "f7", "g7", "g6", "g5", "g4", "g3", "g2", "f2", "e2", "d2", "c2"]
        let phase4 = ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "b8", "c8", "d8", "e8", "f8", "g8", "h8", "h7", "h6", "h5", "h4", "h3", "h2", "h1", "g1", "f1", "e1", "d1", "c1", "b1"]
        let phase5: [String] = [] // All LEDs OFF
        
        return [phase0, phase1, phase2, phase3, phase4, phase5]
    }
    
    private func runLEDAnimation(pattern: [[String]]) {
        var phaseIndex = 0
        
        func nextPhase() {
            if phaseIndex < pattern.count {
                changeLEDs(squares: pattern[phaseIndex])
                phaseIndex += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    nextPhase()
                }
            }
        }
        
        nextPhase()
    }
    
    func changeLEDs(squares: [String]) {
        guard let writeChar = writeCharacteristic else { return }
        
        let convLetter: [Character: UInt8] = ["a": 128, "b": 64, "c": 32, "d": 16, "e": 8, "f": 4, "g": 2, "h": 1]
        let convNumber: [Character: Int] = ["1": 7, "2": 6, "3": 5, "4": 4, "5": 3, "6": 2, "7": 1, "8": 0]
        
        var ledArray = [UInt8](repeating: 0x00, count: 8)
        
        for square in squares {
            if square.count == 2 {
                let file = square[square.startIndex]
                let rank = square[square.index(square.startIndex, offsetBy: 1)]
                
                if let letterValue = convLetter[file], let numberIndex = convNumber[rank] {
                    ledArray[numberIndex] |= letterValue
                }
            }
        }
        
        var command = BtCommands.setLedsPrefix
        command.append(contentsOf: ledArray)
        
        connectedPeripheral?.writeValue(command, for: writeChar, type: .withResponse)
    }
    
    private func handleBoardData(_ data: Data) {
        // Debounce: Ignore updates within 100ms unless board state changes
        let currentTime = Date()
        if let lastTime = lastUpdateTime, currentTime.timeIntervalSince(lastTime) < 0.1, data.subdata(in: 2..<34) == boardState {
            return
        }
        lastUpdateTime = currentTime
        
        if data.count >= 34 && data.prefix(2) == BtResponses.headBuffer {
            let boardData = data.subdata(in: 2..<34)
            if boardData != boardState {
                boardState = boardData
                let asciiBoard = boardStateAsASCII()
                print("BlueNutConnect: Board state updated")
                onBoardUpdate?(asciiBoard)
                onRawBoardData?(boardData)
            }
        } else {
            print("BlueNutConnect: Invalid board data format")
        }
    }
    
    private func handleMiscData(_ data: Data) {
        if data == BtResponses.heartbeatCode {
            return // Skip heartbeat
        }
        print("BlueNutConnect: Received misc data: \(data)")
    }
}

// MARK: - CBCentralManagerDelegate
extension blueNutConnect: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            onScanResult?("Bluetooth is powered off")
        case .resetting:
            onScanResult?("Bluetooth is resetting")
        case .unauthorized:
            onScanResult?("Bluetooth is unauthorized")
        case .unknown:
            onScanResult?("Bluetooth state is unknown")
        case .unsupported:
            onScanResult?("Bluetooth is not supported")
        @unknown default:
            onScanResult?("Unknown bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        guard let name = peripheral.name else { return }
        
        // Check if this is a Chessnut Air device
        for deviceName in deviceList {
            if name.contains(deviceName) {
                if !discoveredPeripherals.contains(peripheral) {
                    discoveredPeripherals.append(peripheral)
                    onScanResult?("Found: \(name) (\(peripheral.identifier))")
                }
                break
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectedPeripheral = peripheral
        peripheral.delegate = self
        onConnectionChange?(true, "Connected to \(peripheral.name ?? "Unknown")")
        
        // Discover services
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onConnectionChange?(false, "Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectedPeripheral = nil
        writeCharacteristic = nil
        onConnectionChange?(false, "Disconnected")
    }
}

// MARK: - CBPeripheralDelegate
extension blueNutConnect: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case BtCharacteristics.write:
                writeCharacteristic = characteristic
            case BtCharacteristics.readBoardData:
                readBoardCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case BtCharacteristics.readMiscData:
                readMiscCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case BtCharacteristics.readOtbData:
                readOtbCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        
        // Send initialization command if we have the write characteristic
        if let writeChar = writeCharacteristic {
            peripheral.writeValue(BtCommands.initCode, for: writeChar, type: .withResponse)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { 
            print("BlueNutConnect: No data received for characteristic \(characteristic.uuid)")
            return 
        }
        
        switch characteristic.uuid {
        case BtCharacteristics.readBoardData:
            handleBoardData(data)
        case BtCharacteristics.readMiscData:
            handleMiscData(data)
        case BtCharacteristics.readOtbData:
            print("BlueNutConnect: Received OTB data: \(data)")
        default:
            print("BlueNutConnect: Unknown characteristic data")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("BlueNutConnect: Write error: \(error)")
        }
    }
}
