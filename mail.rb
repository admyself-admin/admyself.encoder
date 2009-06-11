require 'action_mailer'

ActionMailer::Base.delivery_method = :smtp  
ActionMailer::Base.smtp_settings = {	  
  :address => "mail.railsfactory.com",	
  :domain => "railsfactory.com",
  :port	=> 25,	 
  :authentication => :login,	  
  :user_name => "mailer@railsfactory.com",	  
  :password => "mail3r" 
  }  
ActionMailer::Base.perform_deliveries = true  
ActionMailer::Base.raise_delivery_errors = true  
ActionMailer::Base.default_charset = "utf-8"

class Emailer < ActionMailer::Base
  def test_email(user_email,error,reason)
    subject    "Encoding Script Error - #{error}"
    from       "admyself@railsfactory.org"
    recipients user_email
    body	self.content(error,reason)
  end

def content(error,reason)
" Error : #{error} "
" Reason : #{reason} "
end

end
