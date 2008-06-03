  require "rubygems"
  require 'aws/s3'
  include AWS::S3
  require 'mysql'
  require 'yaml'
  require 'mail'

class MediafileEncoding
  $settings = YAML::load(File.open(File.dirname(__FILE__) + '/mediafile_encoding_settings.yml'))  
  $log = File.open($settings['log'],'a')
  
  def mysql_connect
    db_host=$settings["db_host"]
    db_username=$settings["db_username"]
    db_password=$settings["db_password"]
    db_name=$settings["db_name"]
    db_port=$settings["db_port"]          
    $log.write("\nEstablishing connection with Mysql...\n")
    begin      
      $log.write("Connecting to MySQL database server\n")
      $dbh = Mysql.connect(db_host, db_username, db_password, db_name, db_port)
      $log.write("successfully connected to MySQL server\n")
      $log.write("\n#{'*'*50}Script started...#{Time.now}....#{'*'*50}\n")    
    rescue  Mysql::Error => e
      $log.write("Failed to connect MySQL database server\n")
      $log.write("MysqlError: Can't Connect DB\n\tReason:-> Code:#{e.errno}\tMessage:#{e.error}\t")
      e.respond_to?("sqlstate") ? $log.write("SQLSTATE:#{e.sqlstate} <-:\n") : $log.write(" <-:\n")
    end  #sql begin-rescue-end
  end
  
  def s3connect    
    begin
      $log.write("Connecting to AWS S3...\n")
      AWS::S3::Base.establish_connection!(
                  :access_key_id     => $settings["access_key_id"],
                  :secret_access_key => $settings["secret_access_key"]
                )
      $log.write("AWS S3 connection established successfully...\n")
    rescue
      $log.write("Failed To Connect AWS S3...")
    end  
  end
  
  def fetch_records
    begin
      $log.write("Retrieving datas from Media File Table...\n")
      @result =$dbh.query("SELECT * FROM mediafiles WHERE (is_encoding = 0)")
      #puts @result.num_rows 
      $log.write("Success...\n")
      return @result
    rescue
      $log.write("failed to fetch records from database...\n")
      return false
    end
  end

  def encoding(result)
    s3connect    
    result.each_hash do |x| 	 
      $log.write("\nProcessing Media File ID: #{x['id']} ...\n")	
      $log.write("filename is #{x['filename']}...\n")      
      temp_file = "#{$settings["temp_file_path"]}"+"\\\\"+x['filename'].split(".").first+".flv"
      #puts temp_file
      temp_path = "#{$settings["temp_file_path"]}"+"\\\\"+x['filename']
      #puts temp_path
      @file = x['filename'].split(".").first+".flv"
      #puts temp_file
        begin
          $log.write("\nDownloading #{x['filename']} from s3...\n")          
          #system("c:\\curl-7.18.0\\curl http://s3.amazonaws.com/digital-production/mediafiles/1/2_1.jpg > c:\\abc.jpg")         
          system("#{$settings['curl_path']}/curl #{$settings['s3path']}/#{x['id']}/#{x['filename']} > #{temp_path}")
          $log.write("media file #{x['filename']} downloaded...\n")
        rescue
          $log.write("\n s3 Error: Can't download #{$settings['s3path']}/#{x['id']}...\n\t Reason:->\t#{" unknown "}\t<-:\n")
        end

        begin
          $log.write("\n Encoding downloaded files...")
          puts "#{$settings['tvc_path']} /f #{$settings["temp_file_path"]}"+"\\\\"+"#{x['filename']} /o #{temp_file} /pi #{$settings["flv_ini_file_path"]} /pn Flash video normal quality"
          system("#{$settings['tvc_path']} /f #{$settings["temp_file_path"]}"+"\\\\"+"#{x['filename']} /o #{temp_file} /pi #{$settings["flv_ini_file_path"]} /pn Flash video normal quality")
          $log.write("media file #{x['id']} encoded successfully...\n")
        rescue
           $log.write("\n\tEncode Error: Can't encode this media file #{x['filename']} \n\tReason:->\t#{" unknown "}\t<-:\n")
        end

       begin
          $log.write("uploading encoded files...\n")          
          puts "#{$settings['curl_path']}/curl -T #{temp_file} #{$settings['s3path']}/#{x['id']}/#{x['filename']} "
          system("#{$settings['curl_path']}/curl -T #{temp_file} #{$settings['s3path']}/#{x['id']}/#{x['filename']}")
          $log.write("\n Successfully uploaded...")
          @update_result = $dbh.query("update mediafiles set is_encoding = '1' where id=#{x['id']}")      
          $log.write("\n Status saved in database...")
          #FileUtils.rm "#{$settings["temp_file_path"]}/#{x['filename']}" if File.exists?("#{$settings["temp_file_path"]}/#{x['filename']}")
          #FileUtils.rm "#{temp_file}" if File.exists?("#{temp_file}")
        rescue
          $log.write("socket connection to the server was not read from or written to within the timeout period .Idle connections will be closed ...\n")
          $log.write("Encoded file #{x['filename']} is failed to upload ...\n Process Terminated for #{x['filename']} Media File ID: #{x['id']}...\n")
        end
    end		
  end
  
  def mail_error(error,reason) 
    email_addresses = $settings['recipients'].split(',')
    begin
    email_addresses.each do |e|
      Emailer.deliver_test_email(e.strip,error,reason)
    end
    rescue
    end
 end # def ends
end

  obj = MediafileEncoding.new
  obj.mysql_connect ? @fetch_records=obj.fetch_records : obj.mail_error("MysqlconnectionError")
  if @fetch_records   
    obj.encoding(@fetch_records) ? obj.mail_error("Task Completed","File Encoded and Uploaded Successfully") : obj.mail_error("S3FileError","socket connection to the server was not read from or written to within the timeout period .Idle connections will be closed") 
  else
    obj.mail_error("Unable to fetch Records from database....Try Again Later")
  end