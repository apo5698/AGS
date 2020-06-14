require 'colorize'
require 'open3'

class GradingController < ApplicationController
  before_action :set_variables
  before_action :set_students, only: %w[prepare compile run checkstyle summary]

  def index(the_class)
    @assignments = the_class.all
    if flash[:modal_error]
      @assignment = Assignment.find_by(id: params[:assignment_id])
      @assignment = the_class.new unless @assignment
      @assignment.assign_attributes(assignment_params)
    end
  end

  def new(the_class)
    @assignment = the_class.new
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create
    @assignment = Assignment.create(assignment_params)
    @messages = @assignment.errors.full_messages
    assignment_type = assignment_params[:type].downcase
    if @messages.blank?
      if assignment_type != 'Homework'
        assignment_path = @user_root.join(assignment_type.downcase.pluralize, @assignment.id.to_s)
        FileHelper.create dir: assignment_path.join('submissions')
      end
      flash[:success] = "#{@assignment.name} has been successfully created."
    else
      flash[:modal_error] = @messages.uniq.reject(&:blank?).join(".\n") << '.'
    end
    redirect_to action: 'index', assignment_type => assignment_params.to_h
  end

  def prepare
    render '/grading/show'
  end

  def compile
    render 'grading/show'
  end

  def compile_all
    exec_ret = Array.new(2, '')
    files = Dir.glob(@src_path.join('*.java'))
    if files.empty?
      flash[:error] = 'No file found.'
    else
      cp_path = @bin_path.to_s
      cp_path << ":#{@public_lib_path.join('junit', '*')}" if params[:compile][:options][:junit].to_i == 1

      files.each do |file|
        ret = GradingHelper.exec('javac',
                                 '-d',
                                 @bin_path,
                                 '-cp',
                                 cp_path,
                                 file,
                                 params[:compile][:arg])
        exec_ret[0] << (ret[0] + "\n\n") unless ret[0].empty?
        exec_ret[1] << (ret[1] + "\n\n") unless ret[1].empty?
      end
      if exec_ret[1].empty?
        flash.now[:success] = 'Compile successfully.'
        @console_output = 'Nothing wrong happened.'
      else
        flash.now[:error] = 'Error occurs during compilation. '\
                            'Please check the console output.'
        @console_output = exec_ret[1]
      end
    end

    @action = 'compile'
    compile
  end

  def run
    render '/grading/show'
  end

  def run_selected
    file = params[:run][:file]
    if file.nil?
      flash.now[:error] = 'No file selected.'
    else
      cp_path = @bin_path.to_s
      junit_pkg = ''
      if params[:run][:options][:junit].to_i == 1
        cp_path << ":#{@public_lib_path.join('junit', '*')}"
        junit_pkg = 'org.junit.runner.JUnitCore'
      end

      exec_ret = GradingHelper.exec('java',
                                    '-cp',
                                    cp_path,
                                    junit_pkg,
                                    file.gsub('.class', ''),
                                    params[:run][:arg])
      if exec_ret[1].empty?
        flash.now[:success] = 'Run successfully.'
      else
        flash.now[:error] = 'Error occurs during running. '\
                            'Please check the console output.'
      end
      @console_output = exec_ret[0] + exec_ret[1]
    end

    @action = 'run'
    run
  end

  def checkstyle
    render '/grading/show'
  end

  def checkstyle_run
    cs_path = '~/cs-checkstyle/checkstyle'
    @cs_count = {}
    params[:checkstyle][:files]&.each do |f|
      next if f[1].to_i.zero?

      filename = f[0]
      file_type = !filename.end_with?('Test.java') ? @src_path : @test_path
      filepath = file_type.join(File.basename(filename))
      stdout = GradingHelper.exec(cs_path, filepath)[0].split("\n")

      stdout = stdout.grep(/#{filename}:.+/)
      options = params[:checkstyle][:options]
      stdout = stdout.grep_v(/is a magic number/) if options[:ignore_magic_numbers].to_i == 1
      stdout = stdout.grep_v(/Missing a Javadoc comment/) if options[:ignore_javadoc].to_i == 1
      @cs_count[:"#{filename}"] = stdout.count
    end
    flash.now[:error] = 'No file selected.' if @cs_count.empty?
    @action = 'checkstyle'
    checkstyle
  end

  def summary
    render '/grading/show'
  end

  def upload
    if params[:upload].nil?
      flash[:error] = 'No file selected.'
    else
      uploaded_file = params[:upload][:file]
      begin
        GradingHelper.upload(uploaded_file, @upload_root)
        flash[:success] = 'Upload successfully.'
      rescue StandardError => e
        flash[:error] = e.message
      end
      filename = uploaded_file.original_filename
      GradingHelper.unzip(@upload_root.join(filename), @upload_root.join('submissions')) if filename.match(/.+\.zip/)
    end

    redirect_to "/grading/#{@assignment_type}/#{@id}/prepare"
  end

  def delete_upload
    delete_files = params[:delete_upload].select { |_, v| v.to_i == 1 }
                                         .keys
                                         .map! { |f| File.join(@user_root, f) }
    delete_files = delete_files.first if delete_files.length == 1
    GradingHelper.delete!(delete_files)
    begin
      flash[:success] = 'Delete successfully.'
    rescue StandardError => e
      flash[:error] = e.message
    end
    redirect_to "/grading/#{@assignment_type}/#{@id}/prepare"
  end

  def destroy
    assignment = Assignment.find(params[:id])
    name = assignment.name
    @id = assignment.id
    assignment.destroy
    flash[:success] = "#{name} has been successfully deleted"
    redirect_to action: 'index'
  end

  def edit
    @assignment = Assignment.find(params[:id])
    respond_to do |format|
      format.html
      format.js
    end
  end

  def update
    @assignment = Assignment.find(params[:id])
    @assignment.update_attributes(assignment_params)
    assignment_type = assignment_params[:type].downcase
    messages = @assignment.errors.full_messages
    if messages.blank?
      flash[:success] = "#{@assignment.name} has been successfully updated."
    else
      flash[:modal_error] = messages.uniq.reject(&:blank?).join(".\n") << '.'
    end
    redirect_to action: 'index', assignment_type => assignment_params, assignment_id: params[:id]
  end

  private

  def set_variables
    @assignment_type = params[:controller]
    @id = params[@assignment_type.singularize + '_id']
    @action = params[:action]
    set_paths
  end

  def set_paths
    public_path = Rails.root.join('public')
    @public_lib_path = public_path.join('lib')
    @user_root = public_path.join('uploads', 'users', session[:user].email)
    @upload_root = @user_root.join(@assignment_type, @id) if @id
    @src_path = @upload_root&.join('src')
    @test_path = @upload_root&.join('test')
    @bin_path = @upload_root&.join('bin')
    @lib_path = @upload_root&.join('lib')
  end

  def set_students
    @students = FileHelper.filenames(@upload_root&.join('submissions'))
  end

  def remove_subdirectories(base_path)
    FileHelper.remove base_path
  end
end
