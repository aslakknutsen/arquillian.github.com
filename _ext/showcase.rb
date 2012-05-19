require 'rubygems'
require 'git'
require 'ostruct'
require 'rexml/document'

require File.join File.dirname(__FILE__), 'tweakruby'

class ShowcaseComponent
    #include Base
    def repository()
        @repository
    end

    def initialize()
        @apis = {
            'Arquillian JUnit' => /^org.jboss.arquillian.junit/,
            'Arquillian TestNG' => /^org.jboss.arquillian.testng/,
            #'Arquillian Test' => /^org.jboss.arquillian.test/,
            #'Arquillian Container Test' => /^org.jboss.arquillian.container.test/,
            #'Arquillian Core' => /^org.jboss.arquillian.core/,
            #'Arquillian Config' => /^org.jboss.arquillian.config/,
            'Arquillian Ajocado' => /^org.jboss.arquillian.ajocado/,
            'Arquillian Graphene' => /^org.jboss.arquillian.graphene/,
            'Arquillian Drone' => /^org.jboss.arquillian.drone/,
            'Arquillian Persistence' => /^org.jboss.arquillian.persistence/,
            'Arquillian Spring' => /^org.jboss.arquillian.spring/,
            'Arquillian Extension' => /^org.jboss.arquillian.*(spi)/,
            'ShrinkWrap' => /^org.jboss.shrinkwrap.api/,
            'ShrinkWrap Resovler' => /^org.jboss.shrinkwrap.resolver/,
            'ShrinkWrap Descriptor' => /^org.jboss.shrinkwrap.descriptor/,
            'JSFUnit' => /^org.jboss.jsfunit/,
            'Infinispan' => /^org.infinispan/,
            'RestEasy' => /^org.jboss.resteasy/,
            'JUnit' => /^org.junit/,
            'TestNG' => /^org.testng/,
            'Fest' => /^org.fest/,
            'Selenium' => /^org.openqa.selenium/,
            'Spring JDBC' => /^org.springframework.jdbc/,
            'Spring JMS' => /^org.springframework.jms/,
            'Spring' => /^org.springframework.beans/,

            # Specs
            'AtInject' => /^javax.inject/,
            'CDI' => /^javax.enterprise/,
            'Servlet' => /^javax.servlet/,
            'Persistence' => /^javax.persistence/,
            'JSF' => /^javax.faces/,
            'OSGi' => /^org.osgi/,
            'EJB' => /^javax.ejb/,
            'JMS' => /^javax.jms/,
            'WebService' => /^javax.jws/,
            'Jsr250' => /^javax.annotation/,
            'JaxRS' => /^javax.ws.rs/,
            'Transaction' => /^javax.transaction/,
            'Validation' => /^javax.validation/,
            'Security' => /^java.security/
        }
        @repository = OpenStruct.new({
            :clone_dir => "../arquillian.github.com_repos/arquillian-showcase",
            :type => "git",
            :http_url => "https://github.com/arquillian/arquillian-showcase",
            :relative_path => "",
            :host => "github.com",
            :clone_url => "git://github.com/arquillian/arquillian-showcase.git",
            :desc => "Showcase",
            :owner => "arquillian",
            :path => "arquillian-showcase"
        })
        @repository.client = Git.open @repository.clone_dir
    end

    def handles(repository)
        "arquillian-showcase".eql? repository.path
    end

    def execute(site)
        showcase = visit(@repository, site)
        site.showcases = []
        showcase.marshal_dump().each_value do |val|
            # TODO: Exclude these sooner
            next if val.name.nil? #cdi/gradle-wrapper
            next if val.name =~ /.*(parent|aggregator).*/i

            page = site.engine.load_site_page('showcase/_showcase.html.haml')
            page.output_path = "/showcase/#{val.module_name}.html"
            page.title = val.name
            puts "Created Showcase #{val.module_path} #{val.name}"
            puts "Readme at #{val.readme_path}"
            page.showcase = val
            page.showcase.repository = @repository

            site.showcases << page
        end

        site.pages.concat(site.showcases)
    end
    
    def visit(repository, site)
        
        rc = repository.client

        showcase_mods = OpenStruct.new

        rev = "HEAD:"
        rc.gtree(rev).full_tree.collect do |e|
            if e =~ /[0-9]+ [a-z]+ ([a-z0-9]+).(.*)/
                sha = $1
                path = $2

                #puts path
                module_path = nil;

                if path =~ /(.*)\/src.*/
                    module_path = $1
                elsif path =~ /([a-z\-\/0-9\.]+)\/.*/
                    module_path = $1
                end

                # Ignore the Container BOM modules
                if !module_path.nil? and !(module_path =~ /.*container-bom.*/)
                    module_name = module_path.gsub("/", "-")
                    #puts "#{module_name} #{path}"
                    
                    showcase_mods[module_name] = OpenStruct.new if showcase_mods[module_name].nil?
                    mod = showcase_mods[module_name]

                    #puts "#{module_name} => #{path}"
                    mod.module_name = module_name
                    mod.module_path = module_path if mod.module_path.nil?

                    mod.readme_path = path if path =~ /.*README.*/
                    if path =~ /.*\/pom\.xml/
                        parse_pom(mod, rc.cat_file(sha)) 
                        #puts "#{module_name} #{mod.name} #{path}"
                    end
                    
                    if path =~ /.*\.java/
                        content = rc.cat_file(sha)
                        parse_imports(mod, content)
                        parse_testcase(mod, path, content) if path =~ /(TestCase|Test)\.java$/
                    end
                    
                end
            end
        end

        #puts showcase_mods
        return showcase_mods
    end

    def parse_pom(mod, content)
        pom = REXML::Document.new(content)
        mod.name = pom.root.text('name')
        mod.name.gsub!(/Arquillian Showcase.\s?/, "") if !mod.name.nil?
        mod.name.gsub!(":", " -") if !mod.name.nil?
        mod.description = pom.root.text('description')

        pom.root.each_element("profiles/profile/id") { |id|
            mod.profiles = [] if mod.profiles.nil?
            mod.profiles << id.text
        }
        mod.profiles.sort if !mod.profiles.nil?
    end

    def parse_imports(mod, content)
        mod.apis = Set.new if mod.apis.nil?
        mod.technologies = Set.new if mod.technologies.nil?
        
        content.scan(/^import (static )?(.+?);/) do |match|
            stmt = match[1]
            @apis.each do |key, value| 
                if stmt =~ value
                    mod.apis.add stmt
                    mod.technologies.add key.to_s
                    break
                end
            end
            #puts stmt unless known_apis.include? stmt
        end
    end

    def parse_testcase(mod, path, content)
        mod.tests = [] if mod.tests.nil?

        test = OpenStruct.new
        test.path = path
        test.name = path.match(/.*\/([A-Z][A-Za-z]+)\.java/)[1]
        test.content = content.match(/.*(package .*)/m)[1]
        test.content = content.gsub(/\/\*(?!\*).*Licensed.+?\*\//m, '') #remove /* xxx */ license headers
        if test.content =~/\/\*(.+?)\*\//m
            test.description = $1
            test.description.gsub!(/.?\*.?/, '')
        end
        test.content.gsub!(/\/\*.+?\*\//m, '') #remove /* comments */ license headers
        
        mod.tests << test
    end
end


site = OpenStruct.new

show = ShowcaseComponent.new
#showcase = show.visit(show.repository, site)

#puts showcase.

#showcase.marshal_dump().each {|key, val|
#    puts "#{key} - #{val.name}" #if key =~ /.*spring.*/
#}
#if show.handles(repository)
