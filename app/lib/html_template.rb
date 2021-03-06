module HTMLTemplate

  def tooltip(title)
    "data-toggle='tooltip' title='#{title}'"
  end

  def badge(type, text, pill: false, tooltip: nil)
    type = type.to_sym
    color = case type
            when :success
              'success'
            when :error
              'primary'
            when :danger
              'danger'
            when :info
              'info'
            when :warning
              'warning'
            when :light
              'secondary'
            when :dark
              'dark'
            else
              raise ArgumentError, "invalid type #{type}"
            end

    "<span class=\"badge #{'badge-pill' if pill} badge-#{color}\" #{tooltip(tooltip) if tooltip}>"\
    "#{text}</span>".html_safe
  end

  def badge_checkmark(tooltip = nil)
    badge(:success, '✓', pill: true, tooltip: tooltip)
  end

  def badge_exclamation(tooltip = nil)
    badge(:danger, '!', pill: true, tooltip: tooltip)
  end

  def badge_crossmark(tooltip = nil)
    badge(:error, '✕', pill: true, tooltip: tooltip)
  end

  def new_breadcrumb
    @breadcrumb ||= []
  end

  def breadcrumb_for(url, title = nil)
    # recursive
    if title.nil?
      tokens = url.split('/').reject(&:empty?)
      path = '/'

      tokens.each_with_index do |p, index|
        # normal (home, settings, about, ...)
        if p.to_i.zero?
          name = p.capitalize
        else
          # followed by id (+courses/:course_id+ or +assignments/:assignment_id+)
          class_name = tokens[index - 1].capitalize.singularize.constantize
          # query for record name (#to_s ignored)
          name = class_name.find(p)
        end

        new_breadcrumb << {title: name, url: path = File.join(path, p)}
      end
    else
      # only once
      new_breadcrumb << {title: title, url: url}
    end
  end

  def progress_bar(percentage)
    color = case percentage
            when 100
              'bg-success'
            when 70..99
              'bg-danger'
            else
              ''
            end

    "<div class='progress'>
     <div class='progress-bar progress-bar-striped #{color}' role='progressbar' style='width: #{percentage}%;' aria-valuenow='#{percentage}' aria-valuemin='0' aria-valuemax='100'>
     <span class='text-white'>#{percentage}%</span>
     </div>
     </div>".html_safe
  end
end
