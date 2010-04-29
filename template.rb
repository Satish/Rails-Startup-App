#SOURCE_PATH = "/home/satish/projects/Rails3/Rails-Startup-App"
SOURCE_PATH = "http://github.com/Satish/Rails-Startup-App/raw/master"

def source_path(relative_path)
  File.join(SOURCE_PATH, relative_path)
end

def templates_path(path)
  source_path('templates/' + path )
end

def download_file(path)
   open(templates_path(path)).read
end

def current_app_name
  File.basename(File.expand_path('.'))
end

def remove_js_files
  run "rm -f public/javascripts/*"
  run "touch -f public/javascripts/application.js"
end

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Initial setup"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# Delete unnecessary files
run "rm public/index.html"
#run "rm public/favicon.ico"
run "rm public/images/rails.png"
run 'rm README'
run 'touch README'

git :init

file ".gitignore", download_file("gitignore")

["reset.css", "style.css"].each do |file_name|
  file "public/stylesheets/#{ file_name }", download_file(file_name)
end
run 'touch  public/stylesheets/ie.css'

# Create constants.rb to initializers
initializer 'constants.rb', download_file("constants.rb")

# Tell git to hold empty directories
run %{ find . -type d -empty | grep -v ".git" | xargs -I xxx touch xxx/.gitignore }

# Copy database.yml to database.yml.example
run "cp config/database.yml config/database.yml.example"

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Database support"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

database_yml= YAML.load_file(File.join('config', 'database.yml')).symbolize_keys
development_config = database_yml[:development].symbolize_keys

unless development_config[:adapter] =~ /sqlite/
  db_name, db_username, db_password = development_config[:database], development_config[:username], development_config[:password]

  asked_db_name = ask( "\nPlease enter the development database name (default: #{ db_name })")

  asked_db_username = ask("\nPlease enter the database username (default: #{ db_username })")
  db_username = asked_db_username if asked_db_username.present?

  asked_db_password = ask("\nPlease enter the database password (default: #{ db_password })")
  db_password = asked_db_password if asked_db_password.present?

  #Replace database name in database.yml
  if db_name != asked_db_name
    gsub_file "config/database.yml", /(#{ Regexp.escape("database: #{ db_name }") })/mi do |match|
      "database: #{ asked_db_name }"
    end
  end

  #Replace database username in database.yml
  gsub_file "config/database.yml", /(#{ Regexp.escape("username: root") })/mi do |match|
    "username: #{ db_username }"
  end

  #Replace database password in database.yml
  gsub_file "config/database.yml", /(#{ Regexp.escape("password:") })/mi do |match|
   "password: #{ db_password }"
  end
end

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Choose Sessions storage option default to cookie"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

if yes?("\nWould you like to use the database for sessions instead of the cookie-based default (y/n)")
  rake 'db:sessions:create'
  gsub_file 'config/initializers/session_store.rb', /# ActionController::Base.session_store = :active_record_store/, "ActionController::Base.session_store = :active_record_store"
end

#Initial commit
git :add => "."
git :commit => "-a -m 'Initial commit'"

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Choose Javascript Framework"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

asked_js_framework = ask("\nWhat javascript framework do you want to use (default: prototype)?\n(1) Prototype\n(2) jQuery\n(3) MooTools\n(4) Skip")
javascript_include_tag_options = case asked_js_framework
when '2'
  remove_js_files
  plugin "jrails", :git => "git://github.com/aaronchi/jrails.git"
  '"jquery-ui", "jquery", "jrails", "application"'
when '3'
  remove_js_files
  run "curl -L http://mootools.net/download/get/mootools-1.2.4-core-yc.js > public/javascripts/mootools.js"
  '"mootools.js", "application"'
else
  ':defaults'
end

if ['2', '3'].include?(asked_js_framework)
  git :add => "."
  git :commit => "-a -m 'Javascript framework Prototype Replaced with #{ asked_js_framework == '2' ? 'jQuery' : 'MooTools' }'"
end

sudo = yes?("\nDo you want to use sudo to install gems(y/n)?")

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Install Authlogic Plugin/Gem"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
ask_authlogic = ask("\nWhat option would you like to use for authlogic ( default: plugin)?\n(1) Gem\n(2) Plugin")
case ask_authlogic
when '1'
  gem 'authlogic', :source => 'http://gemcutter.org'
  rake "gems:install", :sudo => sudo
else
  plugin 'authlogic', :git => "git://github.com/binarylogic/authlogic.git"
end

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Choose User model and controller names"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

asked_user_class_name = ask("\nWhat should be the user class name (default: User)")
user_class_file_path = (asked_user_class_name.present? ? asked_user_class_name.strip : 'user' ).underscore

user_class_name = user_class_file_path.camelize
user_table_name = user_class_name.gsub("::", "").tableize
user_class_file_name = user_class_file_path.split('/').last

generate "model #{ user_class_file_path } --skip-migration"

file "app/models/#{ user_class_file_path }.rb", <<-END
class #{ user_class_name } < ActiveRecord::Base

  acts_as_authentic do |c|
    #c.validates_length_of_password_field_options :minimum => 6
    c.perishable_token_valid_for 1.day.to_i
  end

  def deliver_password_reset_instructions!
    reset_perishable_token!
    NotifierMailer.deliver_password_reset_instructions(self)
  end

end
END

file "db/migrate/#{ Time.now.utc.strftime('%Y%m%d%H%M%S') }_create_#{ user_table_name }.rb", <<-END
class Create#{ user_table_name.camelize } < ActiveRecord::Migration
  def self.up
    create_table :#{ user_table_name } do |t|
      t.string    :login,               :null => false                # optional, you can use email instead, or both
      t.string    :email,               :null => false                # optional, you can use login instead, or both
      t.string    :crypted_password,    :null => false                # optional, see below
      t.string    :password_salt,       :null => false                # optional, but highly recommended
      t.string    :persistence_token,   :null => false                # required
      t.string    :single_access_token, :null => false                # optional, see Authlogic::Session::Params
      t.string    :perishable_token,    :null => false                # optional, see Authlogic::Session::Perishability

      # Magic columns, just like ActiveRecord's created_at and updated_at.
      # These are automatically maintained by Authlogic if they are present.
      t.integer   :login_count,         :null => false, :default => 0 # optional, see Authlogic::Session::MagicColumns
      t.integer   :failed_login_count,  :null => false, :default => 0 # optional, see Authlogic::Session::MagicColumns
      t.datetime  :last_request_at                                    # optional, see Authlogic::Session::MagicColumns
      t.datetime  :current_login_at                                   # optional, see Authlogic::Session::MagicColumns
      t.datetime  :last_login_at                                      # optional, see Authlogic::Session::MagicColumns
      t.string    :current_login_ip                                   # optional, see Authlogic::Session::MagicColumns
      t.string    :last_login_ip                                      # optional, see Authlogic::Session::MagicColumns
      t.timestamps
    end

    add_index :#{ user_table_name }, :login
    add_index :#{ user_table_name }, :email
    add_index :#{ user_table_name }, :persistence_token
    add_index :#{ user_table_name }, :perishable_token
    add_index :#{ user_table_name }, :last_request_at
  end

  def self.down
    drop_table :#{ user_table_name }
  end
end
END

user_controller_file_path = user_class_file_path.pluralize
asked_user_controller_name = ask("\nWhat should be the user controller name (default: #{ user_controller_file_path })")

user_controller_file_path = asked_user_controller_name.strip.underscore if asked_user_controller_name.present?
user_controller_name = user_controller_file_path.camelize
user_controller_modules = user_controller_file_path.dup.split('/')
user_controller_file_name = user_controller_modules.pop

user_variable_name = "#{ user_class_file_name.singularize }"
user_instance_variable = "@#{ user_variable_name }"

account_path = "#{ user_controller_file_path.singularize.gsub('/', "_") }_path"
signup_path = (user_controller_modules + ["signup_path"]).join('_')

generate "controller #{ user_controller_file_path }"

file "app/controllers/#{ user_controller_file_path }_controller.rb", <<-END
class #{ user_controller_name }Controller < ApplicationController
  before_filter :require_no_#{ user_variable_name }, :only => [:new, :create]
  before_filter :require_#{ user_variable_name }, :only => [:show, :edit, :update]
  
  def new
    #{ user_instance_variable } = #{ user_class_name }.new
  end
  
  def create
    #{ user_instance_variable } = #{ user_class_name }.new(params[:#{ user_variable_name }])
    if #{ user_instance_variable }.save
      flash[:notice] = "Account registered!"
      redirect_back_or_default #{ account_path }
    else
      render :action => :new
    end
  end
  
  def show
    #{ user_instance_variable } = @current_#{ user_variable_name }
  end

  def edit
    #{ user_instance_variable } = @current_#{ user_variable_name }
  end
  
  def update
    #{ user_instance_variable } = @current_#{ user_variable_name } # makes our views "cleaner" and more consistent
    if #{ user_instance_variable }.update_attributes(params[:#{ user_variable_name }])
      flash[:notice] = "Account updated!"
      redirect_to #{ account_path }
    else
      render :action => :edit
    end
  end
end
END

route <<-END
  map.with_options :controller => :#{ user_controller_file_name } do |controller|
    controller.signup '/signup', :action => :new, :conditions => { :method => :get }
    controller.resource :#{ user_controller_file_name.singularize }, :only => [:show, :create, :edit, :update] 
  end
END

file "app/views/#{ user_controller_file_path }/new.html.erb",  <<-END
<h1 class = "pageHeading">Register</h1>

<% form_for #{ user_instance_variable }, :url => #{ account_path } do |f| %>
  <%= f.error_messages %>
  <%= render :partial => "form", :object => f %>
  <%= f.submit "Register" %>
<% end %>
END

file "app/views/#{ user_controller_file_path }/edit.html.erb",  <<-END
<h1 class = "pageHeading">Edit My Account</h1>

<% form_for #{ user_instance_variable }, :url => #{ account_path } do |f| %>
  <%= f.error_messages %>
  <%= render :partial => "form", :object => f %>
  <%= f.submit "Update" %>
<% end %>

<br /><%= link_to "My Profile", #{ account_path } %>

END

file "app/views/#{ user_controller_file_path }/_form.html.erb", <<-END
<%= form.label :login %><br />
<%= form.text_field :login %><br />
<br />
<%= form.label :email %><br />
<%= form.text_field :email %><br />
<br />
<%= form.label :password, form.object.new_record? ? nil : "Change password" %><br />
<%= form.password_field :password %><br />
<br />
<%= form.label :password_confirmation %><br />
<%= form.password_field :password_confirmation %><br />
END

file "app/views/#{ user_controller_file_path }/show.html.erb", <<-END
<p><b>Login:</b><%= h #{ user_instance_variable }.login %></p>
<p><b>Login count:</b><%= h #{ user_instance_variable }.login_count %></p>
<p><b>Last request at:</b><%= h #{ user_instance_variable }.last_request_at %></p>
<p><b>Last login at:</b><%= h #{ user_instance_variable }.last_login_at %></p>
<p><b>Current login at:</b><%= h #{ user_instance_variable }.current_login_at %></p>
<p><b>Last login ip:</b><%= h #{ user_instance_variable }.last_login_ip %></p>
<p><b>Current login ip:</b><%= h #{ user_instance_variable }.current_login_ip %></p>

<%= link_to 'Edit', edit_#{ account_path } %>
END

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Choose Session Class and Controller Names"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

session_class_name = "#{ user_class_name }Session"
asked_session_class_name = ask("\nWhat should be the session class name (default: #{ session_class_name })?")

session_class_name = asked_session_class_name.strip.camelize if asked_session_class_name.present?
session_class_file_path = session_class_name.underscore
session_class_file_name = session_class_file_path.split('/').last

#generate "session #{ session_class_name }"
file "app/models/#{ session_class_file_path }.rb", <<-END
class #{ session_class_name } < Authlogic::Session::Base

  self.remember_me_for = 7.days
  self.remember_me = true

end
END

session_controller_name = "#{ session_class_name.pluralize }"
asked_session_controller_name = ask("\nWhat should be the session controlller name (default: #{ session_controller_name })?")
session_controller_name = asked_session_controller_name.strip.camelize if asked_session_controller_name.present?

session_controller_file_path = session_controller_name.underscore
session_controller_modules = session_controller_file_path.dup.split('/')
session_controller_file_name = session_controller_modules.pop

session_variable_name = "#{ session_class_file_name.singularize }"
session_instance_variable = "@#{ session_variable_name }"

generate "controller #{ session_controller_file_path }"

session_path = "#{ session_controller_file_path.singularize.gsub('/', '_') }_path"
login_path = (session_controller_modules + ["login_path"]).join('_')
logout_path = (session_controller_modules + ["logout_path"]).join('_')

file "app/controllers/#{ session_controller_file_path }_controller.rb", <<-END
class #{ session_controller_name }Controller < ApplicationController

  #ssl_allowed :create, :destroy# if Rails.env.production?

  before_filter :require_no_#{ user_variable_name }, :only => [:new, :create]
  before_filter :require_#{ user_variable_name }, :only => :destroy

  def new
    session[:return_to] = params[:return_to] if params[:return_to]
    #{ session_instance_variable } = #{ session_class_name }.new
  end

  def create
    #{ session_instance_variable } = #{ session_class_name }.new(params[:#{ session_variable_name }])

    if #{ session_instance_variable }.save
      respond_to do |format|
        format.html do
          flash[:message] = "Login successful!"
          @current_#{ user_variable_name } = #{ session_instance_variable }.#{ user_variable_name }
          redirect_back_or_default(#{ account_path })
        end
        format.js
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:error] = "Please correct the below errors before login."
          render :action => :new
        end
        format.js
      end
    end
  end

  def destroy
    current_#{ user_variable_name }_session.destroy
    flash[:message] = "You have been logged out successfully!"
    redirect_to new_#{ session_path }
  end

end

END

file "app/views/#{ session_controller_file_path }/new.html.erb", <<-END
<h1 class = "pageHeading">Login</h1>

<% form_for #{ session_instance_variable }, :url => #{ session_path } do |f| %>
  <%= f.error_messages %>
  <%= f.label :login %><br />
  <%= f.text_field :login %><br />
  <br />
  <%= f.label :password %><br />
  <%= f.password_field :password %><br />
  <br />
  <%= f.check_box :remember_me %><%= f.label :remember_me %><br />
  <br />
  <%= f.submit "Login" %>
<% end %>
END


file "app/views/layouts/application.html.erb", <<-END
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">

<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <title><%= h(yield(:title) || "#{ current_app_name.titleize }") %></title>
    <%= stylesheet_link_tag "reset", "style" %>
    <!--[if IE]>
      <%= stylesheet_link_tag "ie" %>
    <![endif]--> 
    <%= javascript_include_tag #{ javascript_include_tag_options }, :cache => true %>
  </head>
  <body>
    <div class="container">
      <%= render "shared/header" %>
      <%= yield %>
      <%= render "shared/footer" %>
    </div>
  </body>
</html>
END

file "app/views/shared/_flash.html.erb", <<-END
<div style = "clear:both" id = "flashContainer">
  <% [:message,:error,:notice].each do |key| -%>
    <% if flash[key] -%>
      <div class = "flash" id = "flash_<%= key -%>"><%= flash[key] %></div>
    <% end -%>
  <% end -%>
</div>
END

file "app/views/shared/_header.html.erb", <<-END
<div id = "header">
  <h1 id = "logoContainer"><a href="/" class="logo">#{ current_app_name.titleize }</a></h1>

  <ul class = "topBar">
    <% if logged_in? -%>
      <li class="last"><%= link_to "Logout", #{ logout_path }, :method => :delete, :confirm => "Are you sure you want to logout?", :class=>""-%></li>
      <li class=""><%= link_to "My Account", #{ account_path }, :class=>"" -%></li>
      <li class="first">Welcome <span class="" id = "userNameHeader"><%= h(@current_#{ user_variable_name }.login) -%></span></li>
    <% else -%>
      <li class="last"><%= link_to "Register", #{ signup_path }, :class => "signupLink" -%></li>
      <li class="first"><%= link_to "Log In", #{ login_path }, :class => "loginLink" -%></li>
    <% end -%>
  </ul>
</div>
<%= render :partial => 'shared/flash', :object => flash -%>
<div class="navigation">
  <ul>
    <li class="first"><%= link_to "Home", '/' -%></li>
  </ul>
</div>
END

file "app/views/shared/_footer.html.erb", <<-END
<div id="footer">
  <div class="wrapper">
    <div class="block"></div>
    <div class="copyright">
      Copyright  &copy; <%= Date.today.year -%>,  YOUR APP NAME. All rights reserved.
    </div>
  </div>
</div>
END

file 'app/controllers/application_controller.rb', <<-CODE
class ApplicationController < ActionController::Base

  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  # Scrub sensitive parameters from your log
  filter_parameter_logging :password, :password_confirmation
  helper_method :current_#{ user_variable_name }_session, :current_#{ user_variable_name }, :logged_in?

  private

  def logged_in?
    !!current_#{ user_variable_name }
  end

  def current_#{ user_variable_name }_session
    return @current_#{ user_variable_name }_session if defined?(@current_#{ user_variable_name }_session)
    @current_#{ user_variable_name }_session = #{ session_class_name }.find
  end

  def current_#{ user_variable_name }
    return @current_#{ user_variable_name } if defined?(@current_#{ user_variable_name })
    @current_#{ user_variable_name } = current_#{ user_variable_name }_session && current_#{ user_variable_name }_session.record
  end

  def require_#{ user_variable_name }
    unless current_#{ user_variable_name }
      store_location
      flash[:notice] = "You must be logged in to access this page"
      redirect_to new_#{ session_path }
      return false
    end
  end

  def require_no_#{ user_variable_name }
    if current_#{ user_variable_name }
      store_location
      flash[:notice] = "You must be logged out to access this page"
      redirect_to #{ account_path }
      return false
    end
  end

  def store_location
    session[:return_to] = request.request_uri
  end

  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end

end
CODE

route <<-END
  map.resource :#{ session_controller_file_name.singularize }, :only => [:new, :create, :destroy]
  map.with_options :controller => :#{ session_controller_file_name } do |controller|
    controller.logout '/logout', :action => :destroy, :conditions => { :method => :delete }
    controller.login '/login', :action => :new, :conditions => { :method => :get }
  end
END

git :add => "."
git :commit => "-a -m 'Added authlogic authentication'"

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Generate Code for Password Reset Functionality"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

if yes?("\nDo you want to implement password reset functionality(y/n)?")

password_reset_controller_file_path = "password_resets" 
asked_password_reset_controller_name = ask("\nWhat should be the name of the password reset controller(default: #{ password_reset_controller_file_path })?")
password_reset_controller_file_path = asked_password_reset_controller_name.strip.underscore if asked_password_reset_controller_name.present?


#session_controller_modules = session_controller_file_path.dup.split('/')
#session_controller_file_name = session_controller_modules.pop
#session_variable_name = "#{ session_controller_file_name.singularize }"

password_reset_controller_name = password_reset_controller_file_path.camelize
password_reset_controller_modules = password_reset_controller_file_path.dup.split('/')
password_reset_controller_file_name = password_reset_controller_modules.pop

password_reset_path = "#{ password_reset_controller_file_path.singularize.gsub('/', '_') }_path"
password_reset_url = "#{ password_reset_controller_file_path.singularize.gsub('/', '_') }_url"

file "app/controllers/#{ password_reset_controller_file_path }_controller.rb", <<-EOF
class #{ password_reset_controller_name }Controller < ApplicationController
  before_filter :load_#{ user_variable_name }_using_perishable_token, :only => [:edit, :update]
  before_filter :require_no_#{ user_variable_name }

  def new
    #{ user_instance_variable } = #{ user_class_name }.new
  end

  def create
    #{ user_instance_variable } = #{ user_class_name }.find_by_email(params[:#{ user_variable_name }][:email])
    if #{ user_instance_variable }
      #{ user_instance_variable }.deliver_password_reset_instructions!
      flash[:message] = "Instructions to reset your password have been emailed to you. Please check your email."
      redirect_to #{ login_path }
    else
      flash.now[:error] = "No #{ user_variable_name } was found with that email address"
      #{ user_instance_variable } = #{ user_class_name }.new
      render :action => :new
    end
  end

  def edit; end

  def update
    #{ user_instance_variable }.password = params[:#{ user_variable_name }][:password]
    #{ user_instance_variable }.password_confirmation = params[:#{ user_variable_name }][:password_confirmation]
    if #{ user_instance_variable }.save
      flash[:message] = "Password successfully updated"
      redirect_to #{ account_path }
    else
      flash.now[:error] =  "Unable to update your password, try again."
      render :action => :edit
    end
  end

  private

  def load_#{ user_variable_name }_using_perishable_token
    #{ user_instance_variable } = #{ user_class_name }.find_using_perishable_token(params[:id])
    unless #{ user_instance_variable }
      flash[:notice] = "We're sorry, but we could not locate your account. " +
      "If you are having issues try copying and pasting the URL " +
      "from your email into your browser."
      redirect_to #{ login_path }
    end
  end

end
EOF

file "app/views/#{ password_reset_controller_file_path }/new.html.erb", <<-EOF
<h1 class = "pageHeading">Reset Your Password</h1>

<% form_for #{ user_instance_variable }, :url => #{ password_reset_path } do |f| %>
  <%= f.error_messages %>
  <%= f.text_field :email %>
  <%= f.submit "Reset Password" %>
<% end %>
EOF

file "app/views/#{ password_reset_controller_file_path }/edit.html.erb", <<-EOF
<h1 class = "pageHeading">Choose a new password</h1>

<% form_for #{ user_instance_variable }, :url => #{ password_reset_path }(:id => #{ user_instance_variable }.perishable_token), :html => { :method => :put } do |f| %>
  <%= f.error_messages %>
  <%= f.password_field :password %>
  <%= f.password_field :password_confirmation, :label => "Confirm Password" %>
  <%= f.submit "Change Password" %>
<% end %>
EOF

file "app/models/notifier_mailer.rb", <<-EOF
class NotifierMailer < ActionMailer::Base
  default_url_options[:host] = Rails.env.production? ? HOST_NAME : "http://localhost:3000"

  def password_reset_instructions(#{ user_variable_name })
    subject       '[SITE_NAME] Password Reset Instructions'
    from          NOTIFICATIONS_EMAIL
    recipients    #{ user_variable_name }.email
    sent_on       Time.now
    body          :edit_password_reset_url => edit_#{ password_reset_url }(:id => #{ user_variable_name }.perishable_token)
  end

end
EOF

file "app/views/notifier_mailer/password_reset_instructions.html.erb", <<-EOF
A request to reset your password has been made.
If you did not make this request, simply ignore this email.
If you did make this request just click the link below:

<%= link_to "Reset Password", @edit_password_reset_url %>

If the above URL does not work try copying and pasting it into your browser.
If you continue to have problem please feel free to contact us.
EOF

route "map.resource :#{ password_reset_controller_file_name.singularize }, :except => [:index, :show, :destroy]"

git :add => "."
git :commit => "-a -m 'Added password reset functionality.'"

end

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Generate Code for Authorization(Declarative Authorization)"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

if yes?("\nWould you like to implement authorization functionality(y/n)?")
  authorization_install_options = ask("\nWhat option would you like to use for declarative_authorization ( default: plugin)?\n(1) Plugin\n(2) Gem\n(3) Skip")
  case authorization_install_options
  when '2'
    gem "declarative_authorization"
    rake "gems:install", :sudo => sudo
  when '3'
    puts "declarative_authorization skipped"
  else
    plugin "declarative_authorization", :git => "git://github.com/stffn/declarative_authorization.git"
  end
  unless authorization_install_options == '3'
    #Generate Role model
    generate "model Role title:string #{ user_variable_name }:references"
  
    #Add has_many :roles and role_symbols method to user's  class.
    gsub_file "app/models/#{ user_class_file_path }.rb", /(#{ Regexp.escape("class #{ user_class_name } < ActiveRecord::Base") })/mi do |match|
      "#{ match }\n\n  has_many :roles\n  def role_symbols\n    (roles || []).map { |r| r.title.to_sym }\n  end"
    end
  
    gsub_file "app/controllers/application_controller.rb", /(#{ Regexp.escape("helper_method :current_#{ user_variable_name }_session, :current_#{ user_variable_name }, :logged_in?") })/mi do |match|
      "#{ match }\n\n  before_filter :set_current_user\n\n  protected\n  def set_current_user\n    Authorization.current_user = current_#{ user_variable_name }\n  end"
    end
  
    file "config/authorization_rules.rb", download_file("authorization_rules.rb")
  
    git :add => "."
    git :commit => "-a -m 'Added authorization functionality.'"
  end
end

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Install Some other useful gems/plugins into #{ current_app_name }"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

if yes?("\nWould you like to install will paginate (y/n)?")
  will_paginate_install_options = ask("\nWhat option do you want to use for will paginate ( default: plugin)?\n(1) Plugin\n(2) Gem\n(3) Skip")
  case will_paginate_install_options
  when '2'
    gem 'will_paginate', :source => "http://gemcutter.org"
  when '3'
    puts "will_paginate Skipped"
  else
    plugin "will_paginate", :git => "git://github.com/mislav/will_paginate.git"
  end
end

if yes?("\nWould you like to install HoptoadNotifier (y/n)?")
  hoptoad_notifier_install_options = ask("\nWhat option do you want to use for HoptoadNotifier ( default: plugin)?\n(1) Plugin\n(2) Gem\n(3) Skip")
  case hoptoad_notifier_install_options
  when '2'
    gem "hoptoad_notifier"
  when '3'
    puts "HoptoadNotifier Skipped"
  else
    plugin "hoptoad_notifier", :git => "git://github.com/thoughtbot/hoptoad_notifier.git"
  end
  unless hoptoad_notifier_install_options == '3'
     hoptoad_notifier_api_key = ask("\nPlease enter your hoaptoad notifier key")
     initializer "hoptoad.rb",  "#{ "require 'hoptoad_notifier/rails'\n" if Rails::VERSION::MAJOR < 3 && Rails::VERSION::MINOR < 2 }HoptoadNotifier.configure do |config|
  config.api_key = '#{ hoptoad_notifier_api_key }'
end"
  #rake "gems:install", :sudo => sudo
  #generate "hoptoad --api-key #{ hoptoad_notifier_api_key }"
  end
end

if yes?("\nWould you like to install Paperclip/AttachmentFu for attachment management.(y/n)?")
  attachment_management_plugin = ask("\nWhat would you like to install Paperclip or AttachmentFu( default: Paperclip)?\n(1) Paperclip\n(2) AttachmentFu\n(3) Skip")
  unless attachment_management_plugin == '3'
    attachment_plugin_name, attachment_plugin_repo = case attachment_management_plugin
    when '2'
      ["attachment_fu", "git://github.com/technoweenie/attachment_fu.git"]
    else
      ["paperclip", "git://github.com/thoughtbot/paperclip.git"]
    end

    attachment_plugin_install_options = ask("\nWhat option do you want to use for #{  attachment_plugin_name } ( default: plugin)?\n(1) Plugin\n(2) Gem\n(3) Skip")
    case attachment_plugin_install_options
    when '2'
      gem "#{ attachment_plugin_name }"
    when '3'
      puts "#{ attachment_plugin_name } Skipped"
    else
      plugin "'#{ attachment_plugin_name }'", :git => attachment_plugin_repo
    end
  end
end

git :add => "."
git :commit => "-a -m 'Added some useful gems/plugins.'"

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Freeze Latest Rails"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

if yes?("\nWould you like to freeze the latest Rails?(y/n)")
  freeze!
  git :add => "."
  git :commit => "-a -m 'Rails Freezed'"
end

puts "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
puts "Capify application"
puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

if yes?("\nWill you be using Capistrano to deploy your application?(y/n)")
  capify!
  file "config/deploy.rb", <<-EOF
# USAGE: cap staging/production CAPISTRANO TASK
# Example: cap staging deploy:setup

set :application, "set your application name here"
set :repository,  "set your repository location here"
set :keep_releases, 5
set :scm, :git
set :branch, 'master'
set :user, 'rails'
set :use_sudo, false
default_run_options[:pty] = true
ssh_options[:forward_agent] = true
set :deploy_via, :remote_cache
set :git_shallow_clone, 1
set :git_enable_submodules, 1

set :sql_user, 'deploy'     # User which will have all permission on above database
set :sql_pass, 'deploy'     # Password for above user

desc "this task will set credentials for staging server"
task :staging do
  role :web, "your web-server here"  # Your HTTP server, Apache/etc
  role :app, "your app-server here"   # This may be the same as your `Web` server
  role :db,  "your primary db-server here", :primary => true   # This is where Rails migrations will run
  role :db,  "your slave db-server here"

  set :domain, 'set your staging domain name here'
  set :rails_env, :staging
  set :application, "set your staging application name here"
  set :deploy_to, "/home/#{'#{ user }'}/websites/#{ '#{ application }' }"
  set :database, "#{'#{ application }' }"
end

desc "this task will set credentials for beta site"
task :production do
  role :web, "your web-server here"  # Your HTTP server, Apache/etc
  role :app, "your app-server here"   # This may be the same as your `Web` server
  role :db,  "your primary db-server here", :primary => true   # This is where Rails migrations will run
  role :db,  "your slave db-server here"

  set :rails_env, :production
  set :domain, 'set your production domain name here'
  set :application, "set your production application name here"
  set :deploy_to, "/home/#{ '#{ user }' }/websites/#{ '#{ application }' }"
  set :database, "#{ '#{ application }' }"
end

namespace :deploy do

  desc "create database.yml in capistrano shared directory."
  task :create_database_yml, :roles => :app do
db = <<-CMD
production:
  adapter: mysql
  database: #{ '#{ database }' }
  username: #{ '#{ sql_user }' }
  password: #{ '#{ sql_pass }' }
  host: localhost
  encoding: utf8
CMD
     put db, "#{  '#{ shared_path }' }/database.yml"
  end

  desc "Restarting mod_rails with restart.txt"
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "touch #{ '#{ current_path  }' }/tmp/restart.txt"
  end

  [:start, :stop].each do |t|
    desc "#{ '#{ t }' } task is a no-op with mod_rails"
    task t, :roles => :app do ; end
  end

  task :after_symlink, :roles => :app do
    run "ln -nfs #{ '#{ shared_path }' }/database.yml #{ '#{ current_path }' }/config/database.yml"
  end

  task :after_setup, :roles => :app do
    transaction do
      create_database_yml
      db_setup
    end
  end

  desc "Long deploy will throw up the maintenance.html page and run migrations then it restarts and enables the site again."
  task :long do
    transaction do
      update_code
      web.disable
      symlink
      migrate
    end
    restart
    web.enable
    cleanup
  end

  desc "create a DB named :database, grant permission to a user :sql_user with password :sql_pass"
  task :db_setup , :roles => :app do
    sudo "mysqladmin create #{ '#{ database }' } -uUSERNAME -pPASSWORD"
    sudo "mysql -uUSERNAME -pPASSWORD -e \\"grant all on #{ '#{ database }' }.* to #{ '#{ sql_user }'  }@localhost identified by '#{ '#{ sql_pass }' }' \\" "
    puts "#####################################################################\\n"
    puts "Databases '#{ '#{ database }' }' created:"
    puts "User    : '#{ '#{ sql_user }' }'"
    puts "Password: '#{ '#{ sql_pass }' }'"
    puts "\\n#####################################################################"
  end

end
EOF

  git :add => "."
  git :commit => "-a -m 'application capified'"
end

rake "gems:install", :sudo => sudo
rake "db:create"
rake "db:migrate"

puts "\n==============================================================================================="
puts "#                                                                                             #"
puts "#  1. Please update application routes.rb if any of the generated controller is in namespace  #"
puts "#                                                                                             #"
puts "#    Example:                                                                                 #"
puts "#    controller: admin/users_controller.rb                                                    #"
puts "#                                                                                             #"
puts "#    routes should be as bellow                                                               #"
puts "#    map.namespace :admin do |admin|                                                          #"
puts "#      admin.with_options :controller => :users do |controller|                               #"
puts "#      controller.signup '/signup', :action => :new, :conditions => { :method => :get }       #"
puts "#      controller.resource :user, :only => [:show, :create, :edit, :update]                   #"
puts "#    end                                                                                      #"
puts "#                                                                                             #"
puts "==============================================================================================="
