  require "rubygems"
  require 'aws/s3'
  include AWS::S3
  require 'mysql'
  require 'yaml'
  require "#{File.dirname(__FILE__)}/mail"

class MediafileEncoding
  $settings = YAML::load(File.open(File.dirname(__FILE__) + '/mediafile_encoding_settings.yml'))  
  $log = File.open($settings['log'],'a')
  
  def mysql_connect
    db_host=$settings["db_host"]
    db_username=$settings["db_username"]
    db_password=$settings["db_password"]
    db_name=$settings["db_name"]
    db_port=$settings["db_port"]          
    $log.write("\n#{'*'*50}Script started...#{Time.now}....#{'*'*50}\n")    
    $log.write("\nEstablishing connection with Mysql...\n")
    begin      
      $log.write("Connecting to MySQL database server\n")
      $dbh = Mysql.connect(db_host, db_username, db_password, db_name, db_port)
      $log.write("successfully connected to MySQL server\n\n")     
    rescue  Mysql::Error => e
      $log.write("Failed to connect MySQL database server\n")
      $log.write("MysqlError: Can't Connect DB\n\tReason:-> Code:#{e.errno}\tMessage:#{e.error}\t \n\n")
      e.respond_to?("sqlstate") ? $log.write("SQLSTATE:#{e.sqlstate} <-:\n") : $log.write(" <-:\n")
      mail_error("Mysql Connection Error", $! )
      return
    end  #sql begin-rescue-end
  end
  
  def s3connect    
    begin
      $log.write("Connecting to AWS S3...\n")
      AWS::S3::Base.establish_connection!(
                  :access_key_id     => $settings["access_key_id"],
                  :secret_access_key => $settings["secret_access_key"]
                )
      $log.write("AWS S3 connection established successfully...\n\n")
    rescue
      $log.write("Failed To Connect AWS S3...\n\n")
      mail_error("S3 Connection Error", $! )
      return
    end  
  end
  
  def fetch_records
    begin
      $log.write("Retrieving datas from Media File Table...\n\n")
      @result =$dbh.query("SELECT * FROM mediafiles WHERE (is_encoded = 0 && is_uploaded = 1 && encode_start_time is NULL) LIMIT 1")
      result =  @result.fetch_row
      if @result.num_rows > 0         
        $dbh.query("update mediafiles set encode_start_time='#{Time.now.to_s(:db)}' where id= '#{result[0]}'")  
        @result.data_seek(0)
        return @result 
      else
         $log.write("There is no file in the database to be encoded \n")
         exit
      end
    rescue
      $log.write("Failed to fetch records from database...\n\n")
      mail_error("No Record Found", $! )
      return 
    end
  end

  def encoding(result)
    s3connect    
    result.each_hash do |x| 	       
      $log.write("Processing Media File ID: #{x['id']} ...\n")	
      $log.write("Filename is #{x['filename']}...\n")      
      temp_file = "#{$settings["temp_file_path"]}"+"\\\\"+x['filename'].split(".").first+".flv"
      temp_path = "#{$settings["temp_file_path"]}"+"\\\\"+x['filename']
      @file = x['filename'].split(".").first+".flv"
        begin
          $log.write("Download starts at  #{Time.now.to_s(:db)}...\n")
          $log.write("\nDownloading #{x['filename']} from s3...\n")          
          #puts  "#{$settings['curl_path']}/curl #{$settings['s3path']}/#{x['id']}/#{x['filename']} > #{temp_path}"
          system("#{$settings['curl_path']}/curl #{$settings['s3path']}/#{x['id']}/#{x['filename']} > #{temp_path}")
          if File.size(temp_path) == 0
            mail_error("Curl Download Error", "#{$settings['s3path']}/#{x['id']}/#{x['filename']}" )
            return
          end
          $log.write("Download ends at  #{Time.now.to_s(:db)}.... \n")
          $log.write("media file #{x['filename']} downloaded...\n\n")
        rescue
          $log.write("\n Curl Error: Can't download #{$settings['s3path']}/#{x['id']}...\n\t Reason:->\t#{ $! }\t<-:\n\n")
          mail_error("Curl Download Error", $! )
          return
        end
        begin          
          $log.write("Encode starts at  #{Time.now.to_s(:db)}... \n")
          $log.write("\n Encoding downloaded files...\n")
          #puts "#{$settings['tvc_path']} /f #{$settings["temp_file_path"]}"+"\\\\"+"#{x['filename']} /o #{temp_file} /pi #{$settings["flv_ini_file_path"]} /pn Flash video normal quality"
          system("#{$settings['tvc_path']} /f #{$settings["temp_file_path"]}"+"\\\\"+"#{x['filename']} /o #{temp_file} /pi #{$settings["flv_ini_file_path"]} /pn Flash video normal quality")
          $log.write("Encode ends at  #{Time.now.to_s(:db)}")
          $log.write("media file #{x['filename']} encoded successfully...\n\n")          
        rescue
           $log.write("\n\tEncode Error: Can't encode this media file #{x['filename']} \n\tReason:->\t#{" unknown "}\t<-:\n")
           mail_error("File Encode Error", $! )
           return
        end
        begin
          $log.write("upload starts at  #{Time.now.to_s(:db)}... \n")
          $log.write("uploading encoded files...\n")          
          #puts "#{$settings['curl_path']}/curl -T #{temp_file} #{$settings['s3path']}/#{x['id']}/#{x['filename'].split('.').first+'.flv'} "
          system("#{$settings['curl_path']}/curl -T #{temp_file} #{$settings['s3path']}/#{x['id']}/#{x['filename'].split('.').first+'.flv'}")
          $log.write("\n Successfully uploaded...\n")        
          $log.write("upload ends at  #{Time.now.to_s(:db)}.. \n\n")          
          @update_result = $dbh.query("update mediafiles set is_encoded = '1', encode_end_time='#{Time.now.to_s(:db)}' where id=#{x['id']}")      
          $log.write("\n Status saved in database...\n")          
          $log.write("\n Removing Temporary files...\n")          
          FileUtils.rm "#{$settings["temp_file_path"]}/#{x['filename']}" if File.exists?("#{$settings["temp_file_path"]}/#{x['filename']}")
          FileUtils.rm "#{temp_file}" if File.exists?("#{temp_file}")
          $log.write("\n Temporary files are removed...\n\n")          
        rescue
          $log.write("socket connection to the server was not read from or written to within the timeout period .Idle connections will be closed ...\n")
          $log.write("Encoded file #{x['filename']} is failed to upload ...\n Process Terminated for #{x['filename']} Media File ID: #{x['id']}...\n")
          mail_error("Curl Upload Error", $! )
          return
        end
        $log.write("\n#{'*'*50}Script Stopped at...#{Time.now}....#{'*'*50}\n")    
    end		
  end
  
  def mail_error(error,reason) 
    email_addresses = $settings['recipients'].split(',')
    begin
      email_addresses.each do |e|
        Emailer.deliver_test_email(e.strip,error,reason)
      end
      rescue
        $log.write("Error while sending mail: \n Error : #{error} \n Reason : #{reason}")
      end
    end # def ends
  end
  
  obj = MediafileEncoding.new
  obj.mysql_connect ? @fetch_records=obj.fetch_records : obj.mail_error("MysqlconnectionError","Failed to connect MySQL database server")
  if @fetch_records
    obj.encoding(@fetch_records) ? obj.mail_error("Task Completed","File Encoded and Uploaded Successfully") : obj.mail_error("S3FileError","socket connection to the server was not read from or written to within the timeout period .Idle connections will be closed") 
  else
    obj.mail_error("No Records Found", "All files are already enocoded.")
  end