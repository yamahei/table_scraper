require 'zipang'
require 'selenium_util'

module TableScraper
class Runner

    def initialize url, option={}
        @browser = option[:browser] || :chrome
        @convert = option[:convert] || :none
        @hashead = option[:hashead] || true
        @translate = option[:translate] || nil
        _option = option[:operation]
        if _option then
            if _option.class == String then
                @operation = _option.split(";;")
            elsif _option.class == Array then
                @operation = _option
            else
                p _option
                raise StandardError.new "unknown option."
            end
        end
        
        #TODO: headless?
        @url = url
        _set_browser#set browser to @web
        @tables = _get_tables
    end

    def exec table#=>[[:name, :text, :links], ...]
        _data = _get_data_from_table table
        convert(_data)
    end
    def exec_with_xpath xpath
        _set_browser
        result = exec @web.find(:xpath, xpath)
        _quit_browser
        result
    end
    def exec_with_hint hint_str
        _set_browser
        result = exec _get_canditate(hint_str).shift
        _quit_browser
        result
    end
    def convert data
        case @convert
        when :none then
            data
        when :csv then
            data.map{|cols|
                cols.map{|col| 
                    '"' + (col||"").gsub('"', '""') + '"'
                }.join(",")
            }.join("\n")
        when :json then
            JSON.generate(data)
        end
    end

    private
    def _get_data_from_table table
        heads, datas = [], []# { row, col, key, value }
        row_offset, max_row = 0, 0

        table.find_elements(:xpath, ".//tr").each_with_index{|tr, row_index|
            if row_index==0 then
                heads = tr.find_elements(:xpath, "./*").select{|col|
                    ['th', 'td'].include?(col.tag_name)
                }.map.with_index{|col, index|
                    if @hashead then
                        if @translate then
                            Zipang.to_slug(col.text).tr('０-９ａ-ｚＡ-Ｚ', '0-9a-zA-Z').tr(" ", "").gsub("-", "")
                        else
                            "#{index}.#{col.text}"
                        end
                    else 
                        "col_#{index}"
                    end
                }
                row_offset = -1 if @hashead
                next if @hashead #dont parse at header row!
            end
            row_index += row_offset
            max_row = row_index
            
            tr.find_elements(:xpath, "./*").each_with_index{|col, col_index|
                next if !['th', 'td'].include? col.tag_name

                _col = {
                    :row => row_index,
                    :col => col_index,
                    :key => heads[col_index],
                    :text => col.text,
                }
                datas.push(_col.dup)
                col.find_elements(:xpath, ".//a").map{|a|{
                    :text => a.text,
                    :url => a.attribute("href"),
                }}.select{|link|
                    !link[:url].strip.empty?
                }.each_with_index{|link, index|
                    head = "#{heads[col_index] || col_index}_link_text#{index}"
                    heads.push(head) if !heads.include?(head)
                    __col = _col.dup
                    __col[:key], __col[:text] = head, link[:text]
                    datas.push __col
                    head = "#{heads[col_index] || col_index}_link_url#{index}"
                    heads.push(head) if !heads.include?(head)
                    __col = _col.dup
                    __col[:key], __col[:text] = head, link[:url]
                    datas.push __col
                }
            }
        }
        matrix = [heads]
        (0..max_row).each{|row_index|
            row = []
            heads.each{|head|
                col = datas.find{|data|
                    data[:row] == row_index && data[:key] == head
                }
                row.push col ? col[:text] : nil
            }
            matrix.push row
        }
        matrix
    end

    def _set_browser
        if !_is_browser? @web then
            #@web = SeleniumUtil.new @browser
            @web = SeleniumUtil::Browser.new @browser
            @web.navigate @url
            @web.line_operations(@operation) if @operation
        end
    end
    def _quit_browser
        if _is_browser? @web then
            @web.quit
        end
    end
    def _is_browser? browser
        handles = browser && browser.window_handles
        handles.class == Array ? true : false
    end

    def _get_tables #=> [{}, ..]
        #puts "_get_tables"
        _tables = @web.finds(:xpath, '//body//table').map{|table|
            _pathes = _get_pathes_to_element table
            {
                :pathes => _pathes,
                :path => "/#{_pathes.join('/')}",
                :element => table,
            }
        }
        #p _tables
        return _tables
    end
    def _get_pathes_to_element element #=> [full, path, to, element]
        #puts "_get_pathes_to_element:: #{element.tag_name}"
        _pathes, _elm, _name = [], element, ""
        loop{
            if _name == 'body' then
                #p _pathes 
                return _pathes 
            else
                _name, _names = _elm.tag_name, [_elm.tag_name]
                _names += _elm.attribute("class").split(/\s+/).sort
                _pathes.unshift _names.join(".")
                _elm = _elm.find_element(:xpath, '..')
            end
        }
    end

    def _get_canditate hint_str#=>[Selenium::WebDriver::Element, ...]
        #puts "_get_canditate:: #{hint_str}"
        _xpath = "//body//*[contains(text(), '#{hint_str.strip}')]"
        _elm = @web.find :xpath, _xpath
        _pathes = _get_pathes_to_element(_elm)
        _candi = []
        loop{
            if _pathes.empty? then
                #p _candi
                return _candi
            else
                _path = "/#{_pathes.join('/')}"
                _candi += @tables.select{|table|
                    table[:path].start_with? _path
                }.map{|table|
                    table[:element]
                }.select{|element|
                    !_candi.include? element
                }
                _pathes.pop
            end
        }
    end

end#class
end#module
  

if $0 == __FILE__ then
    require 'optparse'
    # example:
    # bundle exec ruby lib/table_scraper/runner.rb -mxpath -q"//table[@class='table-base00 search-table']" -f -t -c"csv" -u"https://data.j-league.or.jp/SFMS01/" -b"chrome" -o"c;id;competition_years2016;;c;id;competition_frame_ids1;;c;id;team_ids10;;c;id;section_months6;;c;id;search"

    HINT, XPATH = "hint", "xpath"
    _opt, option, help = {}, {}, ""
    _methods = "#{HINT} | #{XPATH}"
    _converts = "json | csv | none"
    _browsers = "chrome | firefox"
    OptionParser.new do |opt|
        opt.on('-u', '--url=VALUE', 'target url') {|v| _opt[:url] = v }
        opt.on('-o', '--operation=[VALUE]', 'prev operation script'){|v| option[:operation] = v.split(";;") }
        opt.on('-m', '--method=VALUE', _methods, 'search method') {|v| _opt[:method] = v }
        opt.on('-q', '--query=VALUE', 'query') {|v| _opt[:query] = v }
        opt.on('-f', '--hashead', 'first row is head') {|v| option[:hashead] = true }
        opt.on('-t', '--translate', 'translate ja header to en') {|v| option[:translate] = true }
        opt.on('-b', '--browser=[VALUE]', _browsers, 'browser to use') {|v| option[:browser] = v.to_sym }
        opt.on('-c', '--convert=[VALUE]', _converts, 'convert type') {|v| option[:convert] = v.to_sym }
        opt.parse!(ARGV)
        help = opt.help
    end

    if _opt.length != 3 then
        puts "[ERROR]the length of required arguments is invalid."
        puts help; exit false
    else
        s = TableScraper::Runner.new _opt[:url], option#TODO: browser control
        case _opt[:method]
        when HINT then
            puts s.exec_with_hint _opt[:query]
        when XPATH then
            puts s.exec_with_xpath _opt[:query]
        else
            puts "[ERROR]unknown method #{_opt[:method]}."
            puts help; exit false
        end
    end
end

