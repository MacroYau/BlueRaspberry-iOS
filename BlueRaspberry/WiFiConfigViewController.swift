//
//  WiFiConfigViewController.swift
//  BlueRaspberry
//
//  Created by Macro Yau on 8/7/2018.
//  Copyright © 2018 Macro Yau. All rights reserved.
//

import UIKit

struct Network: Decodable {
    
    init(ssid: String) {
        self.ssid = ssid
        self.selected = nil
        self.flags = nil
        self.isKnown = nil
    }
    
    var ssid: String
    var selected: Bool?
    var flags: String?
    
    var isKnown: Bool? = false
    
    var security: String {
        get {
            return (flags ?? "").contains("WPA") ? "Secured" : ""
        }
    }
    
}

class WiFiConfigViewController: UITableViewController {
    
    typealias ConnectivityService = BlueRaspberryService.ConnectivityService
    typealias WiFiConfigService = BlueRaspberryService.WiFiConfigService
    
    var wifiOn = true
    var connected: Network?
    var availableNetworks: [Network] = [] {
        didSet {
            for oldNetwork in oldValue {
                if let isKnown = oldNetwork.isKnown {
                    for index in 0..<availableNetworks.count {
                        if availableNetworks[index].ssid == oldNetwork.ssid {
                            availableNetworks[index].isKnown = isKnown
                        }
                    }
                }
            }
        }
    }
    var knownNetworks: [Network] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        showPrompt()
        
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(reloadNetworks(_:)), for: .valueChanged)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didDisconnectFromBluetoothPeripheral(_:)),
                                               name: .didDisconnectFromBluetoothPeripheral,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didUpdateValueForGATTCharacteristic(_:)),
                                               name: .didUpdateValueForGATTCharacteristic,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didWriteValueForGATTCharacteristic(_:)),
                                               name: .didWriteValueForGATTCharacteristic,
                                               object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        showPrompt()
        scanNetworks()
    }
    
    @IBAction func cancel(_ sender: Any) {
        dismiss(animated: true)
    }
    
    func showPrompt() {
        if let name = BluetoothManager.shared.peripheralName {
            navigationItem.prompt = "Connect “\(name)” to a Wi-Fi network"
        }
    }
    
    @objc func onWiFiSwitched(_ sender: UISwitch) {
        wifiOn = sender.isOn
        switchWiFi(enabled: wifiOn)
    }
    
    func switchWiFi(enabled: Bool) {
        let value: UInt8 = enabled ? 0x01 : 0x00
        BluetoothManager.shared.writeCharacteristic(uuid: WiFiConfigService.Characteristics.wifiSwitch.uuid,
                                                    ofServiceUUID: WiFiConfigService.uuid,
                                                    value: Data(bytes: [value]))
        
        if enabled {
            BluetoothManager.shared.subscribeCharacteristic(uuid: ConnectivityService.Characteristics.ssid.uuid,
                                                            ofServiceUUID: ConnectivityService.uuid)
        } else {
            connected = nil
            availableNetworks = []
            knownNetworks = []
        }
        
        self.tableView.reloadData()
    }
    
    @objc func reloadNetworks(_ sender: Any) {
        scanNetworks()
    }
    
    func scanNetworks() {
        // Animation
        if let refreshControl = refreshControl, !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }
        
        // Show connected network at first place
        BluetoothManager.shared.readCharacteristic(uuid: ConnectivityService.Characteristics.ssid.uuid,
                                                   ofServiceUUID: ConnectivityService.uuid)
        
        // First queries the known networks from the Pi (quick response as only reading from saved wpa_supplicant.conf),
        // then in its callback store the list, and invoke scanning in its callback. Upon receiving the scan results,
        // compare and remove active networks from the known list, and update UI.
        BluetoothManager.shared.readCharacteristic(uuid: WiFiConfigService.Characteristics.knownNetworks.uuid,
                                                   ofServiceUUID: WiFiConfigService.uuid)
    }
    
    func connect(_ network: Network) {
        guard let flags = network.flags else { return }
        
        var networkDetails: [String : String] = [:]
        
        if flags.contains("EAP") {
            // WPA or WPA2 Enterprise: Hard-coded for eduroam only for now
            let alert = UIAlertController(title: "Sign In to Wi-Fi Network", message: "Enter the password for “\(network.ssid)”.", preferredStyle: .alert)
            
            let joinAction = UIAlertAction(title: "OK", style: .default, handler: { action in
                let username = alert.textFields![0].text!
                let password = alert.textFields![1].text!
                
                networkDetails["ssid"] = network.ssid
                networkDetails["identity"] = username
                networkDetails["password"] = password
                
                // Specific to eduroam
                networkDetails["key_mgmt"] = "WPA-EAP"
                networkDetails["pairwise"] = "CCMP TKIP"
                networkDetails["group"] = "CCMP TKIP"
                networkDetails["eap"] = "PEAP"
                networkDetails["phase1"] = "peapver=0"
                networkDetails["phase2"] = "MSCHAPV2"
                
                self.connect(networkDetails: networkDetails)
            })
            joinAction.isEnabled = false
            alert.addAction(joinAction)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            
            // Username
            alert.addTextField { (textField) in
                textField.placeholder = "Username"
                NotificationCenter.default.addObserver(forName: Notification.Name.UITextFieldTextDidChange,
                                                       object: textField,
                                                       queue: OperationQueue.main) { notification in
                                                        let length = textField.text!.count
                                                        joinAction.isEnabled = (length > 0)
                }
            }
            
            // Password
            alert.addTextField { (textField) in
                textField.placeholder = "Password"
                textField.isSecureTextEntry = true
                NotificationCenter.default.addObserver(forName: Notification.Name.UITextFieldTextDidChange,
                                                       object: textField,
                                                       queue: OperationQueue.main) { notification in
                                                        let length = textField.text!.count
                                                        joinAction.isEnabled = (length >= 8 && length <= 63)
                }
            }
            
            present(alert, animated: true)
        } else if flags.contains("PSK") {
            // WPA-PSK or WPA2-PSK
            let alert = UIAlertController(title: "Sign In to Wi-Fi Network", message: "Enter the password for “\(network.ssid)”.", preferredStyle: .alert)
            
            let joinAction = UIAlertAction(title: "OK", style: .default, handler: { action in
                let password = alert.textFields![0].text!
                
                networkDetails["ssid"] = network.ssid
                networkDetails["psk"] = password
                self.connect(networkDetails: networkDetails)
            })
            joinAction.isEnabled = false
            alert.addAction(joinAction)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            
            alert.addTextField { (textField) in
                textField.placeholder = "Password"
                textField.isSecureTextEntry = true
                NotificationCenter.default.addObserver(forName: Notification.Name.UITextFieldTextDidChange,
                                                       object: textField,
                                                       queue: OperationQueue.main) { notification in
                                                        let length = textField.text!.count
                                                        joinAction.isEnabled = (length >= 8 && length <= 63)
                }
            }
            
            present(alert, animated: true)
        } else {
            // Open network
            let alert = UIAlertController(title: "Unsecured Network", message: "“\(network.ssid)” is an open network that provides no security, and all network traffic would be exposed.", preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "Join", style: .destructive, handler: { action in
                networkDetails["ssid"] = network.ssid
                self.connect(networkDetails: networkDetails)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            
            present(alert, animated: true)
        }
    }
    
    func connect(networkDetails: [String : String]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: networkDetails, options: []) {
            BluetoothManager.shared.writeCharacteristic(uuid: WiFiConfigService.Characteristics.connectNetwork.uuid,
                                                        ofServiceUUID: WiFiConfigService.uuid,
                                                        value: jsonData)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        if !wifiOn {
            return 1
        }
        
        return (knownNetworks.count > 0) ? 3 : 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return (connected != nil) ? 2 : 1
        case 1:
            return availableNetworks.count
        case 2:
            return knownNetworks.count
        default:
            return 0
        }
    }
    
    func networkTableViewCell(tableView: UITableView, at indexPath: IndexPath, with network: Network, connectable: Bool) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = connectable ? .default : .none
        cell.textLabel?.text = network.ssid
        if let connectedSSID = connected?.ssid, network.ssid == connectedSSID {
            cell.detailTextLabel?.text = "Connected"
        } else {
            cell.detailTextLabel?.text = network.security
        }
        cell.detailTextLabel?.textColor = UIColor.gray
        return cell
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 && indexPath.row == 0 {
            let cell = UITableViewCell()
            cell.selectionStyle = .none
            cell.textLabel?.text = "Wi-Fi"
            let wifiSwitch = UISwitch(frame: .zero)
            wifiSwitch.setOn(wifiOn, animated: false)
            wifiSwitch.addTarget(self, action: #selector(onWiFiSwitched(_:)), for: .valueChanged)
            cell.accessoryView =  wifiSwitch
            return cell
        }
        
        var network: Network?
        var connectable = false
        
        switch indexPath.section {
        case 1:
            network = availableNetworks[indexPath.row]
            connectable = true
        case 2:
            network = knownNetworks[indexPath.row]
        default:
            network = connected
        }
        
        return networkTableViewCell(tableView: tableView, at: indexPath, with: network!, connectable: connectable)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 {
            // Connect (and forget if known)
            if let isKnown = availableNetworks[indexPath.row].isKnown, isKnown == true {
                let alertController = UIAlertController(title: availableNetworks[indexPath.row].ssid,
                                                        message: nil,
                                                        preferredStyle: .actionSheet)
                let connectAction = UIAlertAction(title: "Connect", style: .default) { (action) in
                    DispatchQueue.main.async {
                        var networkDetails: [String : String] = [:]
                        networkDetails["ssid"] = self.availableNetworks[indexPath.row].ssid
                        self.connect(networkDetails: networkDetails)
                    }
                }
                alertController.addAction(connectAction)
                let forgetAction = UIAlertAction(title: "Forget This Network", style: .default) { (action) in
                    DispatchQueue.main.async {
                        let ssid = self.availableNetworks[indexPath.row].ssid
                        self.availableNetworks[indexPath.row].isKnown = false
                        BluetoothManager.shared.writeCharacteristic(uuid: WiFiConfigService.Characteristics.forgetNetwork.uuid,
                                                                    ofServiceUUID: WiFiConfigService.uuid,
                                                                    value: ssid.data(using: .utf8)!)
                        self.tableView.reloadData()
                    }
                }
                alertController.addAction(forgetAction)
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                alertController.addAction(cancelAction)
                DispatchQueue.main.async {
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.connect(self.availableNetworks[indexPath.row])
                }
            }
        } else if indexPath.section == 2 || (indexPath.section == 0 && indexPath.row == 1) {
            // Forget
            let ssid = (indexPath.section == 2) ? knownNetworks[indexPath.row].ssid : (connected?.ssid ?? "")
            let alertController = UIAlertController(title: ssid,
                                                    message: nil,
                                                    preferredStyle: .actionSheet)
            let forgetAction = UIAlertAction(title: "Forget This Network", style: .default) { (action) in
                DispatchQueue.main.async {
                    BluetoothManager.shared.writeCharacteristic(uuid: WiFiConfigService.Characteristics.forgetNetwork.uuid,
                                                                ofServiceUUID: WiFiConfigService.uuid,
                                                                value: ssid.data(using: .utf8)!)
                    
                    self.knownNetworks.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                }
            }
            alertController.addAction(forgetAction)
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alertController.addAction(cancelAction)
            DispatchQueue.main.async {
                self.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1:
            return (availableNetworks.count > 0) ? "Available Networks" : nil
        case 2:
            return (knownNetworks.count > 0) ? "Saved Networks" : nil
        default:
            return nil
        }
    }

}

extension WiFiConfigViewController {
    
    @objc func didUpdateValueForGATTCharacteristic(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let characteristicUUID = userInfo["characteristicUUID"] as? String,
            let value = userInfo["value"] as? Data
            else { return }
        
        switch characteristicUUID {
        case ConnectivityService.Characteristics.ssid.uuid:
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                BluetoothManager.shared.unsubscribeCharacteristic(uuid: ConnectivityService.Characteristics.ssid.uuid)
                self.tableView.reloadData()
            }
            
            if let ssid = String(data: value, encoding: .utf8), !ssid.isEmpty {
                BluetoothManager.shared.unsubscribeCharacteristic(uuid: ConnectivityService.Characteristics.ssid.uuid)
                
                if ssid != connected?.ssid || availableNetworks.isEmpty {
                    scanNetworks()
                }
                
                connected = availableNetworks.filter({ $0.ssid == ssid }).first ?? Network(ssid: ssid)
                availableNetworks = availableNetworks.filter { $0.ssid != ssid }
                tableView.reloadData()
            }
        case WiFiConfigService.Characteristics.availableNetworks.uuid:
            if let data = try? JSONDecoder().decode([Network].self, from: value) {
                availableNetworks = data.filter { $0.ssid != connected?.ssid }
                for index in 0..<availableNetworks.count {
                    let ssid = availableNetworks[index].ssid
                    if knownNetworks.filter({ $0.ssid == ssid }).count > 0 {
                        availableNetworks[index].isKnown = true
                        knownNetworks = knownNetworks.filter { $0.ssid != ssid }
                    }
                }
            }
            tableView.reloadData()
            refreshControl?.endRefreshing()
        case WiFiConfigService.Characteristics.knownNetworks.uuid:
            if let data = try? JSONDecoder().decode([Network].self, from: value) {
                knownNetworks = data.filter { $0.ssid != connected?.ssid }
                for index in 0..<knownNetworks.count {
                    knownNetworks[index].isKnown = true
                }
                BluetoothManager.shared.readCharacteristic(uuid: WiFiConfigService.Characteristics.availableNetworks.uuid,
                                                           ofServiceUUID: WiFiConfigService.uuid)
            }
        default:
            break
        }
    }
    
    @objc func didWriteValueForGATTCharacteristic(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let characteristicUUID = userInfo["characteristicUUID"] as? String
            else { return }
        
        if characteristicUUID == WiFiConfigService.Characteristics.connectNetwork.uuid {
            BluetoothManager.shared.subscribeCharacteristic(uuid: ConnectivityService.Characteristics.ssid.uuid,
                                                            ofServiceUUID: ConnectivityService.uuid)
        }
    }
    
    @objc func didDisconnectFromBluetoothPeripheral(_ notification: Notification) {
        dismiss(animated: true)
    }
    
}
