//
// ChatTableViewCell.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//


import UIKit

class ChatTableViewCell: UITableViewCell, UIDocumentInteractionControllerDelegate {

    @IBOutlet var avatarView: AvatarView?
    @IBOutlet var nicknameView: UILabel?;
    @IBOutlet var messageTextView: UILabel!
    @IBOutlet var messageFrameView: UIView?
    @IBOutlet var timestampView: UILabel?
    
    @IBOutlet var previewView: UIImageView?;
    
    fileprivate var previewUrl: URL?;
    
    fileprivate var messageLinkTapGestureRecognizer: UITapGestureRecognizer!;
    fileprivate var previewViewTapGestureRecognizer: UITapGestureRecognizer?;
    
    fileprivate var originalTextColor: UIColor!;
    fileprivate var links: [Link] = [];
    
    fileprivate static let todaysFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateStyle = .none;
        f.timeStyle = .short;
        return f;
    })();
    fileprivate static let defaultFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM, jj:mm", options: 0, locale: NSLocale.current);
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    fileprivate static let fullFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM.yyyy, jj:mm", options: 0, locale: NSLocale.current);
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    
    fileprivate func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! < 1) {
            return ChatTableViewCell.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return ChatTableViewCell.fullFormatter.string(from: ts);
        } else {
            return ChatTableViewCell.defaultFormatter.string(from: ts);
        }
        
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        if messageFrameView != nil {
            originalTextColor = messageTextView.textColor;
            //messageFrameView.backgroundColor = UIColor.li();
            messageFrameView?.layer.masksToBounds = true;
            messageFrameView?.layer.cornerRadius = 6;
        } else {
            originalTextColor = messageTextView.textColor;
            if previewView != nil {
                previewView?.layer.masksToBounds = true;
                previewView?.layer.cornerRadius = 6;
            }
        }
        if avatarView != nil {
            avatarView!.layer.masksToBounds = true;
            avatarView!.layer.cornerRadius = avatarView!.frame.height / 2;
        }
        messageLinkTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(messageLinkTapGestureDidFire));
        messageLinkTapGestureRecognizer.numberOfTapsRequired = 1;
        messageLinkTapGestureRecognizer.cancelsTouchesInView = false;
        messageTextView.addGestureRecognizer(messageLinkTapGestureRecognizer);
        if previewView != nil {
            previewViewTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(previewTapGestureDidFire));
            messageLinkTapGestureRecognizer.cancelsTouchesInView = false;
            previewViewTapGestureRecognizer?.numberOfTapsRequired = 2;
            previewView?.addGestureRecognizer(previewViewTapGestureRecognizer!);
        }
    }


    override func setSelected(_ selected: Bool, animated: Bool) {
        if selected {
            let colors = contentView.subviews.map({ it -> UIColor in it.backgroundColor ?? UIColor.clear });
            super.setSelected(selected, animated: animated)
            selectedBackgroundView = UIView();
            contentView.subviews.enumerated().forEach { (offset, view) in
                if view .responds(to: #selector(setHighlighted(_:animated:))) {
                    view.setValue(false, forKey: "highlighted");
                }
                print("offset", offset, "view", view);
                view.backgroundColor = colors[offset];
            }
        } else {
            super.setSelected(selected, animated: animated);
            selectedBackgroundView = nil;
        }
        // Configure the view for the selected state
    }
    
    func setValues(data text: String?, ts: Date?, id: Int?, nickname: String?, state: DBChatHistoryStore.State, messageEncryption: MessageEncryption = .none, preview: String? = nil, downloader: ((URL,Int)->Void)? = nil) {
        nicknameView?.text = nickname;
        if ts != nil {
            var timestamp = formatTimestamp(ts!);
            switch messageEncryption {
            case .decrypted, .notForThisDevice, .decryptionFailed:
                timestamp = "\(timestamp) \u{1F512}";
            default:
                break;
            }
            if state.direction == .outgoing {
                timestampView?.textColor = UIColor.lightGray;
                switch state.state {
                case .delivered:
                    timestamp = "\(timestamp) \u{2713}";
                case .error:
                    timestampView?.textColor = UIColor.red;
                    timestamp = "\(timestamp) Not delivered\u{203c}";
                default:
                    break;
                }
            }
            timestampView?.text = timestamp;
        } else {
            timestampView?.text = nil;
        }
        self.previewUrl = nil;
        self.previewView?.image = nil;
        
        if messageFrameView != nil {
            self.messageFrameView?.backgroundColor = state.direction == .incoming ? Appearance.current.incomingBubbleColor() : Appearance.current.outgoingBubbleColor();
            self.nicknameView?.textColor = Appearance.current.secondaryTextColor();
            self.messageTextView.textColor = self.originalTextColor;
        } else {
            self.nicknameView?.textColor = Appearance.current.textColor();
            self.messageTextView?.textColor = Appearance.current.textColor();
        }
        
        self.links.removeAll();
        if text != nil {
            var previewRange: NSRange? = nil;
            var previewSourceUrl: URL? = nil;
            let attrText = NSMutableAttributedString(string: text!);
            
            var first = true;
            if let detect = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue | NSTextCheckingResult.CheckingType.date.rawValue) {
                let matches = detect.matches(in: text!, options: .reportCompletion, range: NSMakeRange(0, text!.count));
                for match in matches {
                    var url: URL? = nil;
                    if match.url != nil {
                        url = match.url;
                        if first && id != nil {
                            first = false;
                            if (preview?.hasPrefix("preview:image:") ?? true) {
                                let previewKey = preview == nil ? nil : String(preview!.dropFirst(14));
                                previewView?.image = ImageCache.shared.get(for: previewKey, ifMissing: {
                                    downloader?(url!, id!);
                                })
                                if previewView?.image != nil && previewKey != nil {
                                    previewUrl = ImageCache.shared.getURL(for: previewKey);
                                    previewRange = match.range;
                                    previewSourceUrl = url;
                                }
                            }
                        }
                    }
                    if match.phoneNumber != nil {
                        url = URL(string: "tel:\(match.phoneNumber!.replacingOccurrences(of: " ", with: "-"))");
                    }
                    if match.addressComponents != nil {
                        let query = match.addressComponents!.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                        if query != nil {
                            url = URL(string: "http://maps.apple.com/?q=\(query!)");
                        }
                    }
                    if match.date != nil {
                        url = URL(string: "calshow:\(match.date!.timeIntervalSinceReferenceDate)");
                    }
                    if url != nil {
                        self.links.append(Link(url: url!, range: match.range));
                        attrText.setAttributes([NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue, NSAttributedString.Key.foregroundColor: (Appearance.current.isDark && Settings.EnableNewUI.getBool()) ? UIColor.blue.adjust(brightness: 0.75) : UIColor.blue], range: match.range);
                    }
                }
            }
            if previewSourceUrl != nil && Settings.SimplifiedLinkToFileIfPreviewIsAvailable.getBool() {
                attrText.mutableString.replaceCharacters(in: previewRange!, with: "Link to file");
            }
            if Settings.EnableMarkdownFormatting.getBool() {
                Markdown.applyStyling(attributedString: attrText, font: self.messageTextView.font, showEmoticons: Settings.ShowEmoticons.getBool());
            }
            self.messageTextView.attributedText = attrText;
        } else {
            self.messageTextView.text = text;
        }
        switch state.state {
        case .error:
            if state.direction == .incoming {
                self.messageTextView.textColor = UIColor.red;
            } else {
                self.accessoryType = .detailButton;
                self.tintColor = UIColor.red;
            }
        default:
            self.accessoryType = .none;
            self.tintColor = self.messageTextView.tintColor;
            if messageEncryption == .notForThisDevice || messageEncryption == .decryptionFailed {
                if let messageFrameView = self.messageFrameView {
                    self.messageTextView.textColor = self.originalTextColor.mix(color: messageFrameView.backgroundColor!, ratio: 0.33);
                } else {
                    self.messageTextView.textColor = Appearance.current.textColor();
                }
            }
        }
    }
    
    @objc func actionMore(_ sender: UIMenuController) {
        NotificationCenter.default.post(name: NSNotification.Name("tableViewCellShowEditToolbar"), object: self);
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return super.canPerformAction(action, withSender: sender) || action == #selector(actionMore(_:));
    }
    
    @objc func messageLinkTapGestureDidFire(_ recognizer: UITapGestureRecognizer) {
        guard self.messageTextView.attributedText != nil else {
            return;
        }
        
        let point = recognizer.location(in: self.messageTextView);
        let layoutManager = NSLayoutManager();
        let attrText = self.messageTextView.attributedText!.mutableCopy() as! NSMutableAttributedString;
        attrText.addAttribute(NSAttributedString.Key.font, value: self.messageTextView.font as Any, range: NSRange(location: 0, length: attrText.length));
        let textStorage = NSTextStorage(attributedString: attrText);
        let textContainer = NSTextContainer(size: self.messageTextView.bounds.size);
        textContainer.maximumNumberOfLines = self.messageTextView.numberOfLines;
        layoutManager.usesFontLeading = true;
        textContainer.lineFragmentPadding = 0;
        textContainer.lineBreakMode = self.messageTextView.lineBreakMode;
        layoutManager.addTextContainer(textContainer);
        textStorage.addLayoutManager(layoutManager);
        
        let idx = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil);
        if let url = links.first(where: { link -> Bool in link.contains(idx: idx)}) {
//        if let url = attrText.attribute(NSAttributedString.Key.link, at: idx, effectiveRange: nil) as? NSURL {
            UIApplication.shared.open(url.url);
        }
    }
    
    @objc func previewTapGestureDidFire(_ recognizer: UITapGestureRecognizer) {
        guard self.previewView != nil else {
            return;
        }
        
        let documentController = UIDocumentInteractionController(url: previewUrl!);
        documentController.delegate = self;
        //documentController.presentPreview(animated: true);
        documentController.presentOptionsMenu(from: CGRect.zero, in: self.previewView!, animated: true);
    }
    
    class Link {
        let url: URL;
        let range: NSRange;
        
        init(url: URL, range: NSRange) {
            self.url = url;
            self.range = range;
        }
        
        func contains(idx: Int) -> Bool {
            return range.contains(idx);
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromOptionalNSTextCheckingKeyDictionary(_ input: [NSTextCheckingKey: Any]?) -> [String: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (NSAttributedString.Key(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromNSAttributedStringKey(_ input: NSAttributedString.Key) -> String {
	return input.rawValue
}
