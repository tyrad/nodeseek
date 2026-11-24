require "fastlane_core/itunes_transporter"

# Fastlane 2.233.1 会把 altool 写到成功回执前的续传文件错误也计为上传失败。
module AltoolUploadReceipt
  MISSING_RESUME_FILE = /\A\[ContentDelivery\.Uploader\.[\da-f]+\] Failed to create URL for 'CDUploaderStateInfoResumeFilePath'\. The file doesn['’]t exist\. \(4\) The file doesn['’]t exist\.\z/i
  DELIVERY_UUID = /\ADelivery UUID: [\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}\z/i

  def execute(command, hide_output)
    super do |lines|
      # 此时 Fastlane 已将非零退出码也计入 errors；只有唯一的已知错误可豁免。
      if errors&.one? && errors.first.gsub(/\e\[[\d;]*m/, "").strip.match?(MISSING_RESUME_FILE)
        receipt = lines.map(&:strip)
        delivery = receipt.find { |line| line.match?(DELIVERY_UUID) }
        if delivery && receipt.include?("UPLOAD SUCCEEDED with no errors")
          errors.clear
          FastlaneCore::UI.important("altool 已确认上传成功，忽略续传文件缺失提示。#{delivery}")
        end
      end
      yield(lines) if block_given?
    end
  end
end

FastlaneCore::AltoolTransporterExecutor.prepend(AltoolUploadReceipt)
