final class PeerCell: UITableViewCell {

    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var sendMessageButton: UIButton!
    @IBOutlet weak var sendFileButton: UIButton!

    var onSendMessage: (() -> Void)?
    var onSendFile: (() -> Void)?

    @IBAction func sendMessageTapped() { onSendMessage?() }
    @IBAction func sendFileTapped() { onSendFile?() }
}