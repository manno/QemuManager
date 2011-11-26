#!/usr/bin/ruby
require 'gtk2'
require 'yaml'
require 'fileutils'
#require 'inotify'

=begin

== NAME 

qemu-manager - manage a dir full of qemu images

== SYNOPSIS

qemu-manager

== DESCRIPTION

Manage a dir of qemu images, launch them with specified command

== TODO

  FIX path management, use a data dir
  Startup and Notify
  Confirmation dialog
  Rename

=end
DEFAULT_SCRIPT = 'qemu-all.sh hd %f'
DEFAULT_GLADE = File.join(ENV['HOME'], 'ruby/qemu-manager.xml')

module Qemu
  BASE = File.join(ENV['HOME'], 'qemu')

  class Image
    def initialize(path)
      @path = path
      @name = File.basename(@path)
      get_info
    end
    attr_reader :path, :name, :format, :size, :disk_size, :backing_file

    def get_info
      `qemu-img info #{@path}`.each {|l| 
        l.chomp!
        case l
        when /^file format: /
          @format = l[13..-1]
        when /^virtual size: /
          @size = l[14..-1].sub(/([GM]) .*$/) { |s| $1 }
        when /^disk size: /
          @disk_size = l[11..-1]
        when /^backing file: /
          @backing_file = l.sub(/.* \(actual path: (.*)\)$/) { |s| $1 }
        end
      }
    end
  end

  class DirectoryStore
    def initialize(dir=BASE)
      @dir = dir
      @images = {}
      read_dirs
    end
    attr_reader :images

    def read_dirs
      return unless File.directory?(@dir)
      Dir.open(@dir).each {|f|
        next unless f.match(/\.qcow$/)
        path = File.join(BASE, f)
        @images[path] = Image.new(path)
      }
    end
  end
end

# Gtk Application to manage a QemuStore
#
module QemuManager
 
  # User interaction
  #
  module Actions
    def display_image_info
      found = nil
      @treeview.selection.selected_each {|model, path, iter| found = iter }
      if found
        @current = @qemu_store.images[found[PATH]]
        path = found[PATH]

        # TODO GLib::Markup.escape_text
        descr = <<EOF
<b>Name:</b>
#{found[NAME]}
<i>#{path}</i>

<b>Size:</b>
#{found[DISK_SIZE]} / #{found[SIZE]}
EOF
        descr += "\n<b>Base file:</b>\n#{found.parent[NAME]}\n" if found.parent
        descr += "\n<b>Command Line:</b>\n#{@image_data.cmdlines[path]}" if @image_data.cmdlines[path]
        @glade['label1'].markup =  descr

        @glade['textview1'].buffer.text = ''
        if @current and @image_data.comments[path]
          @glade['textview1'].buffer.text = @image_data.comments[path]
        end
        @glade['textview1'].editable = true
      end
    end

    def format_image_name(name)
      name.sub!(/\..*$/, '')
      case name
      when /-data\d*-/
        '<i>'+ name +'</i>'
      when /-base-/
        '<b>'+ name +'</b>'
      else
        name
      end
    end

    def set_iter(iter, p, i)
      iter[PATH] = p
      iter[NAME] = format_image_name(i.name)
      iter[FORMAT] = i.format
      iter[SIZE] = i.size
      iter[DISK_SIZE] = i.disk_size
    end

    def execute_image
      cmd = "#{@glade['entry1'].text.to_s}"
      return unless @current
      cmd.sub!('%f', @current.path.to_s)
      @image_data.cmdlines[@current.path] = cmd
      log 'gui', cmd
      Thread.new { system cmd }
    end

    def create_image
      cmd = "qemu-img #{@glade['entry2'].text.to_s}"
      log 'gui', cmd
      system cmd
      refresh_treeview(@gclient[GCONF_DIR_KEY])
    end

    def delete_image
      log 'gui', "delete #{@current.path.to_s}"

      dialog = Gtk::MessageDialog.new(@glade['window1'],
                                      Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
                                      Gtk::MessageDialog::WARNING,
                                      Gtk::MessageDialog::BUTTONS_OK_CANCEL,
                                      "Really delete this file?")
      dialog.run do |response|
        if response == Gtk::Dialog::RESPONSE_OK
          File.unlink @current.path
          @image_data.delete(@current.path)
          refresh_treeview(@gclient[GCONF_DIR_KEY])
        end
        dialog.destroy
      end
    end

    def log(ctx,msg)
      #@statusbar.remove(@contexts[ctx], @last) if @last
      #@last = @statusbar.push(@contexts[ctx],msg)
      context = @statusbar.get_context_id(ctx)
      @statusbar.pop(context)
      @statusbar.push(context,msg)
      STDERR.puts("=== #{ctx}: #{msg}") if $DEBUG
    end
  end

  # Callbacks for all our dialog windows
  # 
  module DialogCallbacks
    # Execute Dialog
    #
    def show_execute_dialog
      iter = @treeview.selection.selected
      if iter
        if @image_data.cmdlines[iter[PATH]]
          @glade['entry1'].text = @image_data.cmdlines[iter[PATH]]
        else
          @glade['entry1'].text = @gclient[GCONF_SCRIPT_KEY]
        end
        @glade['label3'].text = iter[NAME]
        @glade['label10'].text = ''
        @glade['label10'].text = 'Warning: trying to boot a backing file' if iter[BACKING]
        @glade['dialog_execute'].show
      end
    end

    def on_button1_clicked
      execute_image
      @glade['dialog_execute'].hide
    end

    def on_button2_clicked
      @glade['dialog_execute'].hide
    end

    def on_dialog_execute_delete_event
      @glade['dialog_execute'].hide
    end

    # Image Tool Dialog
    #
    def show_image_dialog
      iter = @treeview.selection.selected
      if iter
        @glade['label5'].markup = iter[NAME]
        @glade['checkbutton1'].active = true
        f = File.basename(iter[PATH]).sub(/-base-/, '-hostN-')
        @glade['entry2'].text = "create -b #{iter[PATH]} -f qcow2 #{f}"
      else
        
        @glade['entry2'].text = "create -f qcow2 NAME.qcow 4G"
      end
      @glade['dialog_new'].show
    end

    def on_button3_clicked
      @glade['dialog_new'].hide
    end

    def on_button4_clicked
      create_image
      @glade['dialog_new'].hide
    end

    def on_dialog_new_delete_event
      @glade['dialog_new'].hide
    end

    # Preferences Dialog
    #
    def show_preferences_dialog
      @glade['dialog_preferences'].show
    end
    def on_entry3_changed
      @gclient[GCONF_DIR_KEY] = @glade['entry3'].text
    end
    def on_entry4_changed
      @gclient[GCONF_SCRIPT_KEY] = @glade['entry4'].text
    end
    def on_button6_clicked
      @glade['dialog_preferences'].hide
    end

    def on_dialog_preferences_delete_event
      @glade['dialog_preferences'].hide
    end

    # About Dialog
    #
    def on_dialog_about_response
      @glade['dialog_about'].hide
    end
    def on_dialog_about_delete_event
      @glade['dialog_about'].hide
    end

  end

  PROG_NAME = 'Qemu Manager'
  GCONF_PATH = '/apps/qemu-manager'
  GCONF_DIR_KEY = '/apps/qemu-manager/qemu_store_directory'
  GCONF_SCRIPT_KEY = '/apps/qemu-manager/qemu_script_cmdline'
  GCONF_COMMENTS_KEY = '/apps/qemu-manager/comments'
  ( PATH,
    NAME,
    FORMAT,
    SIZE,
    DISK_SIZE,
    BACKING) = *(0..5).to_a

  class ImageData
    def initialize
      @comments = Hash.new
      @cmdlines = Hash.new
    end
    attr_reader :comments, :cmdlines
    attr_writer :comments, :cmdlines

    def delete(path)
      @comments.delete(path)
      @cmdlines.delete(path)
    end

    def rename
      @comments[new_name] = @comments[path]
      @comments.delete(path)
      @cmdlines[new_name] = @cmdlines[path]
      @cmdlines.delete(path)
    end
  end

  class Controller
    #include GetText
    include Actions
    include DialogCallbacks

    def initialize(glade_file)
      #bindtextdomain(PROG_NAME, nil, nil, "UTF-8")
      @glade = Gtk::Builder.new
      @glade.add_from_file( glade_file )
      @glade.connect_signals { |handler| method(handler) }

      @statusbar = @glade['statusbar1']
      #@last = nil;

      @image_data = ImageData.new
      @glade['textview1'].buffer.signal_connect("end-user-action") do 
        puts "=== changed buffer saved" if $DEBUG
        @image_data.comments[@current.path] = @glade['textview1'].buffer.text
      end

      init_gconf
      init_treeview

      # inotify
      #@iclient = Inotify.new
			#@iclient.add_watch(@gclient[GCONF_DIR_KEY], Inotify::CREATE | Inotify::DELETE | Inotify::MOVE)
    end
    attr :glade

    def run
      refresh_treeview(@gclient[GCONF_DIR_KEY])
    end

    def init_gconf
      @gclient = GConf::Client.default
      @gclient.add_dir(GCONF_PATH)

      # default values
      @gclient[GCONF_SCRIPT_KEY] ||= DEFAULT_SCRIPT
      @gclient[GCONF_DIR_KEY] ||= Qemu::BASE

      # preferences window
      @glade['entry3'].text = @gclient[GCONF_DIR_KEY] 
      @glade['entry4'].text = @gclient[GCONF_SCRIPT_KEY]

      # FIXME ruby doesn't support set_list
      if @gclient[GCONF_COMMENTS_KEY] 
          @image_data = YAML::load(@gclient[GCONF_COMMENTS_KEY])
      end
      @image_data = ImageData.new if not @image_data.kind_of?(ImageData)

      # refresh view if gconf changes
      @gclient.notify_add(GCONF_DIR_KEY) { |client,entry|
        if File.directory?(entry.value)
          @glade['entry3'].text = entry.value
          refresh_treeview(entry.value)
        end
      }
      @gclient.notify_add(GCONF_SCRIPT_KEY) { |client,entry|
        @glade['entry4'].text = entry.value
      }
    end

    def on_treeview_cell_edited(cell, path_string, new_text, column)
      path = Gtk::TreePath.new(path_string)
      iter = @treeview.model.get_iter(path)
      path = iter[PATH]
      new_name = File.join(File.dirname(path), new_text) + File.extname(path)
      if new_name != path 
        if iter[BACKING]
          log 'gui',"can't rename base images"
        else
          if FileUtils.mv(path, new_name)
            @image_data.rename(path, new_name)
            iter[column] = format_image_name(new_text)
            iter[PATH] = new_name
            log 'gui',"rename #{path} to #{new_name}"
          else
            log 'gui',"failed rename #{path} to #{new_name}"
          end
        end
      end
    end

    def init_treeview
      @treeview = @glade['treeview1']
      @treeview.search_column = 0

      column = Gtk::TreeViewColumn.new("#", Gtk::CellRendererText.new, {:text => PATH})
      column.visible = false
      @treeview.append_column(column)

      renderer = Gtk::CellRendererText.new
      renderer.editable = true
      renderer.signal_connect('edited') { |*args| on_treeview_cell_edited(*args.push(NAME)) }
      column = Gtk::TreeViewColumn.new("Name", renderer, {:markup => NAME})
      #column = Gtk::TreeViewColumn.new("Name", Gtk::CellRendererText.new, {:markup => NAME})
      column.resizable = true
      column.set_sort_column_id(NAME)
      @treeview.append_column(column)

      column = Gtk::TreeViewColumn.new("Format", Gtk::CellRendererText.new, {:text => FORMAT})
      column.set_sort_column_id(FORMAT)
      @treeview.append_column(column)

      column = Gtk::TreeViewColumn.new("Size", Gtk::CellRendererText.new, {:text => SIZE})
      column.set_sort_column_id(SIZE)
      @treeview.append_column(column)

      column = Gtk::TreeViewColumn.new("Act. Size", Gtk::CellRendererText.new, {:text => DISK_SIZE})
      column.set_sort_column_id(DISK_SIZE)
      @treeview.append_column(column)

      column = Gtk::TreeViewColumn.new("Backing", Gtk::CellRendererToggle.new, {:active => BACKING})
      column.visible = false
      @treeview.append_column(column)

      # show info on click
      @treeview.signal_connect("cursor-changed") do 
        display_image_info
      end
    end
  
    def refresh_treeview(dir)

      # FIXME statusbar update only once?
      if File.directory?(dir)
        Dir::chdir dir 
        log 'load', 'loading store... '
      else
        log 'load', 'please set up your qemu image directory in the preferences'
        return
      end

      @glade['window1'].sensitive = false
      @qemu_store = Qemu::DirectoryStore.new(dir)

      model = Gtk::TreeStore.new(String, String, String, String, String, Object)
      @treeview.set_model(model)

      # add images without backing file
      @qemu_store.images.select { |p,i| i.backing_file.nil? }.sort.each { |p,i| 
        iter = model.append(nil)
        set_iter(iter, p, i)
        iter[BACKING] = false
      }

      # add images with backing files
      @qemu_store.images.select { |p,i| i.backing_file }.each { |p,i|
        # find parent
        parent = nil
        @treeview.model.each {|model, path, iter|
          if File.identical?(iter[PATH], i.backing_file)
              parent = iter
              iter[BACKING] = true
              break
          end
        }
        # add child to parent - works if parent=nil
        iter = model.append(parent)
        set_iter(iter, p, i)
        iter[BACKING] = false
      }
      @treeview.columns_autosize
      @treeview.expand_all
      @glade['window1'].sensitive = true
      log 'load', 'loading store... done'
    end

    # Callbacks
    #
    def on_imagemenuitem_prefs_activate(widget)
      @glade['dialog_preferences'].show
    end
    def on_imagemenuitem_new_activate(widget)
      create_image
    end
    def on_imagemenuitem_about_activate(widget)
      @glade['dialog_about'].show
    end
    def on_imagemenuitem_quit_activate(widget)
      quit
    end

    def on_toolbutton_execute_image_clicked(widget)
      show_execute_dialog
    end
    def on_toolbutton_new_image_clicked(widget)
      show_image_dialog
    end
    def on_toolbutton_delete_image_clicked(widget)
      delete_image
    end
    def on_toolbutton_refresh_clicked(widget)
      refresh_treeview(@gclient[GCONF_DIR_KEY])
    end

    def on_window1_destroy_event
      quit
    end
    def on_window1_delete_event
      quit
    end

    def quit
      @gclient[GCONF_COMMENTS_KEY] = @image_data.to_yaml
      Gtk.main_quit
    end
  end
end

=begin

  Here be dragons

=end
glade_file = DEFAULT_GLADE
if (File.readable? 'qemu-manager.glade')
  glade_file = 'qemu-manager.glade'
end
trap('INT') { $c.quit }

Gtk.init
$c = QemuManager::Controller.new(glade_file)
$c.glade['window1'].show
Thread.start { 
  $c.run
}
Gtk.main
