//
//  MainViewController.swift
//  BlueRaspberry
//
//  Created by Macro Yau on 6/7/2018.
//  Copyright © 2018 Macro Yau. All rights reserved.
//

import UIKit
import AudioToolbox
import CoreBluetooth

class MainViewController: UIViewController {
    
    let proximityConnectThreshold: Int = -40 // dBm
    let scanTimeoutSeconds: Int = 15
    
    typealias ConnectivityService = BlueRaspberryService.ConnectivityService
    
    @IBOutlet weak var instructionStackView: UIStackView!
    @IBOutlet weak var instructionImageView: UIImageView!
    @IBOutlet weak var instructionLabel: UILabel!
    
    @IBOutlet weak var wifiStackView: UIStackView!
    @IBOutlet weak var ssidLabel: UILabel!
    @IBOutlet weak var ipAddressLabel: UILabel!
    @IBOutlet weak var configButton: UIButton!
    
    private var discoveredDevices: [String: String] = [:]
    
    private let defaultSSIDLabelText: String = "Not Connected"
    private let defaultIPAddressLabelText: String = "Acquiring..."
    
    private var instructionState: InstructionState = .noBluetooth {
        didSet {
            setInstructionState(instructionState)
        }
    }
    private var scanTimeoutTask: DispatchWorkItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didUpdateBluetoothState(_:)),
                                               name: .didUpdateBluetoothState,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didDiscoverBluetoothPeripheral(_:)),
                                               name: .didDiscoverBluetoothPeripheral,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didConnectToBluetoothPeripheral(_:)),
                                               name: .didConnectToBluetoothPeripheral,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didDisconnectFromBluetoothPeripheral(_:)),
                                               name: .didDisconnectFromBluetoothPeripheral,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didDiscoverGATTService(_:)),
                                               name: .didDiscoverGATTService,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didUpdateValueForGATTCharacteristic(_:)),
                                               name: .didUpdateValueForGATTCharacteristic,
                                               object: nil)
        
        BluetoothManager.shared.prepare()
        instructionState = .readyToConnect
    }
    
    func scanForPi() {
        instructionState = .readyToConnect
        
        BluetoothManager.shared.startScanning(services: [BlueRaspberryService.uuid],
                                              continuous: true)
        
        scanTimeoutTask = DispatchWorkItem {
            BluetoothManager.shared.stopScanning()
            self.instructionState = .notFound
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(scanTimeoutSeconds),
                                      execute: scanTimeoutTask)
    }
    
    func setInstructionState(_ state: InstructionState) {
        if let imageName = state.imageName {
            instructionImageView.image = UIImage(named: imageName)
        }
        instructionLabel.text = state.message
        configButton.setTitle(state.buttonText, for: .normal)
        configButton.isHidden = (state.buttonText == nil)
        
        setInstructionVisibility(true)
        setWiFiInfoVisibility(false)
    }
    
    func setInstructionVisibility(_ visible: Bool) {
        instructionStackView.isHidden = !visible
    }
    
    func setWiFiInfoVisibility(_ visible: Bool) {
        wifiStackView.isHidden = !visible
        if !visible {
            ssidLabel.text = defaultSSIDLabelText
            ipAddressLabel.text = defaultIPAddressLabelText
        }
    }
    
    func updateSSID(data: Data) {
        var ssidText = defaultSSIDLabelText
        if let ssid = String(data: data, encoding: .utf8) {
            if !ssid.isEmpty {
                ssidText = ssid
            }
        }
        ssidLabel.text = ssidText
    }
    
    func updateIPAddress(data: Data) {
        var ipText = defaultIPAddressLabelText
        if let ip = String(data: data, encoding: .utf8) {
            if !ip.isEmpty {
                ipText = ip
            }
        }
        ipAddressLabel.text = ipText
    }

    @IBAction func didTapButton(_ sender: Any) {
        if BluetoothManager.shared.isConnected {
            performSegue(withIdentifier: "ShowWiFiConfig", sender: self)
            return
        } else {
            switch instructionState {
            case .notFound:
                scanForPi()
            default:
                break
            }
        }
    }
    
}

extension MainViewController {
    
    @objc func didUpdateBluetoothState(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let bluetoothState = userInfo["state"] as? CBManagerState
            else { return }
        
        var state: InstructionState
        switch bluetoothState {
        case .unknown, .unsupported:
            state = .noBluetooth
        case .resetting:
            state = .busy
        case .unauthorized, .poweredOff:
            state = .bluetoothOff
            scanTimeoutTask.cancel()
        case .poweredOn:
            state = .readyToConnect
            scanForPi()
        }
        instructionState = state
    }
    
    @objc func didDiscoverBluetoothPeripheral(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let uuid = userInfo["peripheralUUID"] as? String,
            let rssi = userInfo["rssi"] as? Int
            else { return }

        if rssi < 0 && rssi > proximityConnectThreshold {
            BluetoothManager.shared.stopScanning()
            BluetoothManager.shared.connect(peripheralUUID: uuid)
        }
    }
    
    @objc func didConnectToBluetoothPeripheral(_ notification: Notification) {
        scanTimeoutTask.cancel() // Expire timeout for peripheral scanning
        
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        setInstructionVisibility(false)
        setWiFiInfoVisibility(true)
        
        configButton.setTitle("Manage Wi-Fi Networks", for: .normal)
        configButton.isHidden = false
    }
    
    @objc func didDisconnectFromBluetoothPeripheral(_ notification: Notification) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        setWiFiInfoVisibility(false)
        instructionState = .notFound
        setInstructionVisibility(true)
    }
    
    @objc func didDiscoverGATTService(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let serviceUUID = userInfo["serviceUUID"] as? String
            else { return }
        
        switch serviceUUID {
        case ConnectivityService.uuid:
            BluetoothManager.shared.subscribeCharacteristic(uuid: ConnectivityService.Characteristics.ssid.uuid,
                                                            ofServiceUUID: ConnectivityService.uuid,
                                                            readImmediately: true)
            BluetoothManager.shared.subscribeCharacteristic(uuid: ConnectivityService.Characteristics.ipAddress.uuid,
                                                            ofServiceUUID: ConnectivityService.uuid,
                                                            readImmediately: true)
        default:
            break
        }
    }
    
    @objc func didUpdateValueForGATTCharacteristic(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let characteristicUUID = userInfo["characteristicUUID"] as? String,
            let value = userInfo["value"] as? Data
            else { return }
        
        switch characteristicUUID {
        case ConnectivityService.Characteristics.ssid.uuid:
            updateSSID(data: value)
        case ConnectivityService.Characteristics.ipAddress.uuid:
            updateIPAddress(data: value)
        default:
            break
        }
    }
    
}

extension MainViewController {
    
    enum InstructionState {
        
        case bluetoothOff
        case readyToConnect
        case notFound
        case busy
        case noBluetooth
        
        var message: String {
            switch self {
            case .bluetoothOff:
                return "Turn on Bluetooth to start searching your Raspberry Pi."
            case .readyToConnect:
                return "Hover this device over your Raspberry Pi to connect."
            case .notFound:
                return "It doesn't look like anything to me."
            case .busy:
                return "Bluetooth is busy..."
            case .noBluetooth:
                return "Oops! Bluetooth is not available on this device."
            }
        }
        
        var buttonText: String? {
            switch self {
            case .notFound:
                return "Scan Again"
            default:
                return nil
            }
        }
        
        var imageName: String? {
            switch self {
            case .readyToConnect:
                return "Scan"
            case .notFound:
                return "NotFound"
            default:
                return "BluetoothOff"
            }
        }
        
    }
    
}
