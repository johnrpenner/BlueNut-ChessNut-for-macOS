//
//  ViewController.swift
//  BlueNut • ChessNut Air to Chess Moves for macOS
//	
//  Created by Roland on 2025-09-27.
//	

import Cocoa

class ViewController: NSViewController {
    
    @IBOutlet weak var OutputField: NSTextField!
    @IBOutlet weak var InputField: NSTextField!
    @IBOutlet weak var UCIcommand: NSTextField!
    
    @IBOutlet weak var ScanButton: NSButton!
    @IBOutlet weak var ConnectButton: NSButton!
    @IBOutlet weak var ReadButton: NSButton!
    @IBOutlet weak var SendButton: NSButton!
    
    private var blueNutConnector: blueNutConnect!
    private var blue2UCI: Blue2UCI!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize the BlueNut connector and Blue2UCI
        blueNutConnector = blueNutConnect()
        blue2UCI = Blue2UCI()
        setupBlueNutCallbacks()
        setupBlue2UCICallbacks()
        
        // Set button targets and actions
        ScanButton.target = self
        ScanButton.action = #selector(doScan)
        
        ConnectButton.target = self
        ConnectButton.action = #selector(doConnect)
        
        ReadButton.target = self
        ReadButton.action = #selector(doRead)
        
        SendButton.target = self
        SendButton.action = #selector(doSend)
        
        InputField.isEditable = true
        OutputField.stringValue = "Ready. Click Scan to find devices."
    }
    
    private func setupBlueNutCallbacks() {
        // Set up callbacks for the BlueNut connector
        blueNutConnector.onScanResult = { [weak self] message in
            DispatchQueue.main.async {
                let currentText = self?.OutputField.stringValue ?? ""
                self?.OutputField.stringValue = currentText + "\n" + message
            }
        }
        
        blueNutConnector.onConnectionChange = { [weak self] isConnected, message in
            DispatchQueue.main.async {
                self?.OutputField.stringValue = message
                self?.ConnectButton.title = isConnected ? "Disconnect" : "Connect"
                self?.ReadButton.isEnabled = isConnected
                self?.SendButton.isEnabled = isConnected
            }
        }
        
        blueNutConnector.onBoardUpdate = { [weak self] boardString in
            DispatchQueue.main.async {
                self?.OutputField.stringValue = "Board Updated:\n" + boardString
            }
        }
        
        // Connect raw board data to Blue2UCI for move detection
        blueNutConnector.onRawBoardData = { [weak self] rawData in
            self?.blue2UCI.updateBoardFromData(rawData)
        }
    }
    
    private func setupBlue2UCICallbacks() {
        // Handle move detection from Blue2UCI
        blue2UCI.onMoveDetected = { [weak self] uciMove in
            DispatchQueue.main.async {
                self?.UCIcommand.stringValue = uciMove
                print("ViewController: Updated UCIcommand to: \(uciMove)")
            }
        }
        
        // Handle LED changes from Blue2UCI
        blue2UCI.onLEDChange = { [weak self] squares in
            // Send LED command to the chess board
            if let connector = self?.blueNutConnector {
                connector.changeLEDs(squares: squares)
                print("ViewController: Sent LED command for squares: \(squares)")
            }
        }
    }
    
    @objc func doScan() {
        OutputField.stringValue = "Starting scan..."
        if let sound = NSSound(named: "sfxScanner") { sound.play() }
        
        blueNutConnector.startScanning()
    }
    
    @objc func doConnect() {
        if let sound = NSSound(named: "pickupCoin") { sound.play() }
        
        if ConnectButton.title == "Connect" {
            OutputField.stringValue = "Attempting to connect..."
            blueNutConnector.connectToDevice()
        } else {
            OutputField.stringValue = "Disconnecting..."
            blueNutConnector.disconnectFromDevice()
        }
    }
    
    @objc func doRead() {
        let boardState = blueNutConnector.readBoardPosition()
        OutputField.stringValue = "Current Board Position:\n" + boardState
    }
    
    @objc func doSend() {
        OutputField.stringValue = "Starting LED test pattern..."
        blueNutConnector.sendLEDTestPattern()
        
        // Also handle any input field data if needed
        let inputText = InputField.stringValue
        if !inputText.isEmpty {
            OutputField.stringValue += "\nInput: " + inputText
            InputField.stringValue = ""
        }
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
}
