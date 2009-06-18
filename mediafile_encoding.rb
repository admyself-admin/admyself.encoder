  require "rubygems"
  require 'yaml'
  require "#{File.dirname(__FILE__)}/mail"

class MediafileEncoding
  $settings = YAML::load(File.open(File.dirname(__FILE__) + '/mediafile_encoding_settings.yml'))  
  $log = File.open($settings['log'],'a')
	
	def get_media_files
		post_args = {       
	     'encoding_app_key' => $settings['encoding_app_key']
    }
		
    begin					
		  response, data = Net::HTTP.post_form(URI.parse("#{$settings['app_path']}/mediafiles/get_media_files_for_encoding"), post_args)			      
			if data.include?('success')
				result = eval(data)
				encoding(result, Time.now.to_s(:db))
			elsif data =='fail'
				$log.write("There is no mediafile available for encoding...\n")
				return
			elsif data == 'key_match_failed'
				$log.write("encoding application key match failed.\n")
				mail_error("Key Matching Failed", "Encoding app key doesn't match with the admyself server key. \n" )
				return
			else				
				$log.write("Either the app url #{$settings['app_path']} is incorrect or the server is down...\n")
				mail_error("Get media files Error", "Either the app url #{$settings['app_path']} is incorrect or the server is down...\n" )
				return
			end			
	  rescue		
		  $log.write("#{$!}")
			mail_error("Get media files Error", "Either the app url #{$settings['app_path']} is incorrect or the server is down...#{$!} \n" )
			exit
	  end
		
	end
	
  def encoding(media, encode_start_time)    
      $log.write("Processing Media File ID: #{media['id']} ...\n")	
      $log.write("Filename is #{media['filename']}...\n")      
      temp_file = "#{$settings["temp_file_path"]}"+"\\\\"+media['filename'].split(".").first+".flv"
      temp_path = "#{$settings["temp_file_path"]}"+"\\\\"+media['filename']
      @file = media['filename'].split(".").first+".flv"
        begin
          $log.write("Download starts at  #{Time.now.to_s(:db)}...\n")
          $log.write("\nDownloading #{media['filename']} from s3...\n")          
          puts  "#{$settings['curl_path']}/curl #{$settings['s3path']}/#{media['id']}/#{media['filename']} > #{temp_path}"
          system("#{$settings['curl_path']}/curl #{$settings['s3path']}/#{media['id']}/#{media['filename']} > #{temp_path}")
          if File.size(temp_path) == 0
            mail_error("Curl Download Error", "#{$settings['s3path']}/#{media['id']}/#{media['filename']}" )
            return
          end
          $log.write("Download ends at  #{Time.now.to_s(:db)}.... \n")
          $log.write("media file #{media['filename']} downloaded...\n\n")
        rescue
          $log.write("\n Curl Error: Can't download #{$settings['s3path']}/#{media['id']}...\n\t Reason:->\t#{ $! }\t<-:\n\n")
          mail_error("Curl Download Error", $! )
          return
        end
        begin          
          $log.write("Encode starts at  #{Time.now.to_s(:db)}... \n")
          $log.write("\n Encoding downloaded files...\n")
          puts "#{$settings['tvc_path']} /f #{$settings["temp_file_path"]}"+"\\\\"+"#{media['filename']} /o #{temp_file} /pi #{$settings["flv_ini_file_path"]} /pn Flash video normal quality"
          system("#{$settings['tvc_path']} /f #{$settings["temp_file_path"]}"+"\\\\"+"#{media['filename']} /o #{temp_file} /pi #{$settings["flv_ini_file_path"]} /pn Flash video normal quality")
          $log.write("Encode ends at  #{Time.now.to_s(:db)}")
          $log.write("media file #{media['filename']} encoded successfully...\n\n")          
        rescue
           $log.write("\n\tEncode Error: Can't encode this media file #{media['filename']} \n\tReason:->\t#{" unknown "}\t<-:\n")
           mail_error("File Encode Error", $! )
           return
        end
        begin
          $log.write("upload starts at  #{Time.now.to_s(:db)}... \n")
          $log.write("uploading encoded files...\n")          
          puts "#{$settings['curl_path']}/curl -T #{temp_file} #{$settings['s3path']}/#{media['id']}/#{media['filename'].split('.').first+'.flv'} "
          system("#{$settings['curl_path']}/curl -T #{temp_file} #{$settings['s3path']}/#{media['id']}/#{media['filename'].split('.').first+'.flv'}")
          $log.write("\n Successfully uploaded...\n")        
          $log.write("upload ends at  #{Time.now.to_s(:db)}.. \n\n")                    
          $log.write("\n Removing Temporary files...\n")          
          FileUtils.rm "#{$settings["temp_file_path"]}/#{media['filename']}" if File.exists?("#{$settings["temp_file_path"]}/#{media['filename']}")
          FileUtils.rm "#{temp_file}" if File.exists?("#{temp_file}")
          $log.write("\n Temporary files are removed...\n\n")          
					send_encode_update_status(media, encode_start_time)
        rescue
          $log.write("socket connection to the server was not read from or written to within the timeout period .Idle connections will be closed ...\n")
          $log.write("Encoded file #{media['filename']} is failed to upload ...\n Process Terminated for #{media['filename']} Media File ID: #{media['id']}...\n")
          mail_error("Curl Upload Error", $! )
          return
        end
        $log.write("\n#{'*'*50}Script Stopped at...#{Time.now}....#{'*'*50}\n")
	end
	
	def send_encode_update_status(media, encode_start_time)
		post_args = {       
	     'key' => $settings['app_key'],
			 'mediafile_id' => media['id'],
			 'encoding_start_time'=> encode_start_time,
			 'encoding_end_time'=> Time.now.to_s(:db)
    } 
    begin					
		  response, data = Net::HTTP.post_form(URI.parse("#{$settings['app_path']}/mediafiles/update_status_for_encoded_media_files"), post_args)						
			$log.write("\n Status saved in database...\n")  if data.include?('success')			
	  rescue		
		  $log.write("#{$!}")
	  end
	end
  
  def mail_error(error,reason) 
    email_addresses = $settings['recipients'].split(',')
    begin
      email_addresses.each do |e|
        Emailer.deliver_test_email(e.strip,error,reason)
      end
     rescue
        $log.write("Error while sending mail: \n Error : #{error} \n Reason : #{$!}")
      end
    end # def ends
  end
  
  obj = MediafileEncoding.new
	obj.get_media_files