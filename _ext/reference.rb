require 'rubygems'
require 'ostruct'
require 'git'
require 'json'
require 'json/add/ostruct'

require File.join File.dirname(__FILE__), 'tweakruby'

module Awestruct
	module Extensions
		module Reference

	class JavaDoc
		
		def initialize()
			@cache_file_name = 'references.yml'
		end

		def execute(site)
			reference = load_cache site.tmp_dir
			if reference.nil?

				if !site.resolve_published_artifacts
					puts "Reference can not be extracted without resolve_published_artifacts set to true"
					return
				end
				return if site.modules.nil?

				reference = generate_reference_data site
				reference.merge! generate_reference_data_external site

				find_and_create_outbound_links reference
				find_and_create_inbound_links reference
				calculate_page_rank reference
			end

			add_json_api site, reference
			store_cache site.tmp_dir, reference
		end

		# TMP, this should be moved into the main processing chain somewhere..
		# External Repos we want to scan and include into the Dictionary
		def generate_reference_data_external site
			reference = Hash.new

			external = {
				:shrinkwrap => {
					:path => 'shrinkwrap',
					:clone_url => 'git://github.com/shrinkwrap/shrinkwrap.git',
					:http_url => 'https://github.com/shrinkwrap/shrinkwrap',
					:artifacts => [
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap',
							:artifactId => 'shrinkwrap-api'
						}),
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap',
							:artifactId => 'shrinkwrap-spi'
						})
					]
				},
				:shrinkwrap_resolver => {
					:path => 'shrinkwrap-resolver',
					:clone_url => 'git://github.com/shrinkwrap/resolver.git',
					:http_url => 'https://github.com/shrinkwrap/resolver',
					:artifacts => [
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap.resolver',
							:artifactId => 'shrinkwrap-resolver-api'
						}),
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap.resolver',
							:artifactId => 'shrinkwrap-resolver-api-maven'
						})
					]
				},
				:shrinkwrap_descriptors => {
					:path => 'shrinkwrap-descriptors',
					:clone_url => 'git://github.com/shrinkwrap/descriptors.git',
					:http_url => 'https://github.com/shrinkwrap/descriptors',
					:artifacts => [
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap.descriptors',
							:artifactId => 'shrinkwrap-descriptors-api-base'
						}),
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap.descriptors',
							:artifactId => 'shrinkwrap-descriptors-api-javaee'
						}),
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap.descriptors',
							:artifactId => 'shrinkwrap-descriptors-api-jboss'
						}),
						OpenStruct.new({
							:groupId => 'org.jboss.shrinkwrap.descriptors',
							:artifactId => 'shrinkwrap-descriptors-spi'
						})
					]
				}
			}
			external.each do |path, data|
				clone_dir = File.join(site.repos_dir, path.to_s)
				if !File.directory? clone_dir
					puts "Cloning repository #{data[:clone_url]} -> #{clone_dir}"
					rc = Git.clone(data[:clone_url], clone_dir)
				else
					puts "Using cloned repository #{clone_dir}"
					rc = Git.open(clone_dir)
				end
				latest_version = rc.tags.last.name
				data[:artifacts].each do |artifact|
					puts "Extract Reference Dictionary for #{path} #{latest_version} #{artifact.artifactId}" 
					generate_reference(
						reference, rc, "", artifact, latest_version, data[:http_url])
				end
		    end
		    return reference
		end

		def generate_reference_data(site)
			reference = Hash.new
			site.components.each do |components|
				components.select{|c| c.class == OpenStruct}.each do |component|

					component.releases.select{|r| r.version.eql? component.latest_version}.each do |release|

						release.published_artifacts.select{|a| a.artifactId =~ /.*(api|spi).*/}.each do |artifact|

							puts "Extract Reference Dictionary for #{component.name} #{release.version} #{artifact.artifactId}"

							rc = component.client ||= Git.open(component.repository.clone_dir)
							
							generate_reference(
								reference, rc, component.repository.relative_path, 
								artifact, release.version, component.repository.http_url)
						end
					end
				end
			end
			return reference
		end

		def generate_reference(reference, rc, relative_path, artifact, version, http_url)
			load_all_files(rc, relative_path, artifact.artifactId, version) do |content, file_name, base_path|
				doc = {
					:name => file_name.match(/([A-Z].*)\.java/)[1],
					:package => file_name.gsub(/\//, '.').gsub(/\.[A-Z].*/, ''),
					:file => file_name,
					:artifact_type => artifact.artifactId.match(/.*(api|spi).*/)[1],
					:artifact => {
						:groupId => artifact.groupId,
						:artifactId => artifact.artifactId,
						:packaging => artifact.packaging.to_s,
						:since => calculate_since(rc, "#{base_path}src/main/java/#{file_name}"),
					},
					:repository => {
						:http_url => http_url,
						:base_path => base_path
					},
					:desc => parse_content(content)
					}

				doc_key = "#{doc[:package]}.#{doc[:name]}"
				doc[:key] = doc_key

				if reference.has_key? doc_key
					puts "Warning, duplicate key #{doc_key}"
					puts "#{reference[doc_key][:file]} vs #{doc[:file]}"
				end
				reference[doc_key] = doc
			end
		end

		def load_all_files(rc, relative_path, artifact_name, version)
			if artifact_name =~ /([a-z]+)-([a-z]+)-(.*)/
				rev = nil
				base_path = nil
				# artifact name can be mapped to the structure in a few ways:
				# (arquillian)-(core)-(api) /core/api
				# (arquillian)-(container)-(test-api) /container/test-api
				# (arquillian)-(persistence)-(api) /api
				# (graphane)-(selenium)-(api) /graphane-selenium/graphane-selenium-api
				begin
					base_path = "#{relative_path}#{$2}/#{$3}/"
					rev = rc.revparse("#{version}:#{base_path}")
				rescue
					begin 
						base_path = "#{relative_path}#{$3}/"
						rev = rc.revparse("#{version}:#{base_path}")
					rescue
						begin
							base_path = "#{relative_path}#{$2}-#{$3}/"
							rev = rc.revparse("#{version}:#{base_path}")
						rescue
							base_path = "#{relative_path}#{$1}-#{$2}/#{$1}-#{$2}-#{$3}/"
							rev = rc.revparse("#{version}:#{base_path}")
						end
					end
				end
			elsif artifact_name =~ /([a-z]+)-([a-z]+)/
				base_path = "#{relative_path}#{$2}/"
				rev = rc.revparse("#{version}:#{base_path}")
			end

			if !rev.nil?
				rc.gtree(rev).full_tree.collect {|e| 
					if e =~ /[0-9]+ [a-z]+ ([a-z0-9]+).src\/main\/java\/(.*\.java)/
						sha = $1
						file = $2
						if !(file =~ /.*(SecurityActions|Validate|\.util\.).*/)
							yield(rc.cat_file(sha), file, base_path)
						end
					end
				}
			end
		end

		# Starting from the oldes tags and looping forward
		# first hit based on path is first version it was included
		def calculate_since(rc, path) 
			rc.tags.each do |tag|
				begin
					rc.revparse("#{tag.name}:#{path}")
					return tag.name
				rescue
				end
			end
			return nil
		end

		def parse_content(content)

			class_doc = ''
			if content =~ /(\/\*\*(?!.*Copyright)(.+?)\*\/)+/m # ignore license notices with javadoc comments
				class_doc = $2
			end

			class_doc.gsub!(/ \* ?/, '') # remove * from beginning of line
			class_doc.gsub!(/(<.?p>|<.?pre>|<br.?\/>)/, '') # remove tags
			class_doc.gsub!('&#64;', '@') # replace @ encoding
			class_doc.gsub!(/\{@[a-z]+ ([A-Za-z\#@\(\), ]+)\}/, '\1') # replace {@code|link X} with X
			class_doc.gsub!(/^@[a-z]+.*/m, '') # remove @author ++

			# We fiddle with \n chars which will kill some of the formating in code, temporarly remove it then add it back in when done
			code_snippets = []
			class_doc.gsub!(/(<code>)(.+?)(<\/code>)/m) do |match|
				code_snippets << $2
				"#{$1}X#{$3}"
			end

			class_doc.gsub!(/(?:\B|\S)(\w|\d| |,)\n(\w|\d| )/, '\1 \2') # remove new lines in middle of sentences unless they are 'started' by a end symbol, e.g. . :

			code_snippets.reverse!

			class_doc.gsub!(/(<code>)(X)(<\/code>)/m) do |match|
				code = code_snippets.pop
				"#{$1}#{code}#{$3}"
			end

			class_doc.gsub!(/\n{3,}/, "\n\n") # remove multiple newlines (some left over from removed tags)
			class_doc.gsub!(/code>\n/, "code>")  #code tags normally end with a new line, remove it to avoid newline in formatting
			#class_doc.gsub!(/(\{@code (.+?)\})+/m, '<code>\2</code>') # need bracker matcing to not match to early or to late
			class_doc.strip!

			return class_doc
		end

		def find_and_create_outbound_links(reference)
			# Create a map with the doc:name as and key[] as value. Wiki refs are always based on name, 
			# but we need the key to make a direct match
			name_reference = Hash.new
			reference.each { |key, value|
				name = value[:name]
				if !name_reference.has_key? name
					name_reference[name] = []
				end
				name_reference[name] << key
			}

			reference.each do |key, doc|
				keys = Hash.new

				desc = doc[:desc]

				# Ruby 1.8.7 does not support str.match(exp, pos), so we slice the str to simulate
				# We attempt to match "<space>Aa<space>"
				# unless we move one char back before we attempt to match again we won't match 
				# Bb in this case "<space>Aa<space>Bb<space>"
				exp = /\W([A-Z][a-z]+(?:[A-Z][a-z]+)*)\W/m
				pos = 1;
				end_of_string = false
				while (!end_of_string)
					new_desc = desc[pos...desc.length]
					end_of_string = true if new_desc.nil?
					next if new_desc.nil?

					match = new_desc.match(exp)
					end_of_string = true if match.nil?

					next if match.nil?

					pos = (pos + match.end(0))-1
					match_str = match[1]
					#puts "#{match_str} #{!match_str.eql? doc[:name]}"

					found_refs = name_reference[match_str]
					if !found_refs.nil? and !match_str.eql? doc[:name]
						# TODO: attempt to match most logical reference of multiple are named the same. e.g. if ref in api module pick api ref
						puts "Warning, multiple references found for #{match_str} #{found_refs.join(' ')}" if found_refs.size > 1
						found_key = found_refs[0]
						if(keys.has_key? found_key)
							keys[found_key] = keys[found_key]+1
						else
							keys[found_key] = 1
						end
					end
				end

				doc[:outbound] = keys unless keys.empty?
			end
		end

		def find_and_create_inbound_links(reference)
			reference.each do |key, doc|
				keys = Hash.new
				reference.each do |other_key, other_doc|
					next if other_doc[:outbound].nil?
					if other_doc[:outbound].has_key? key and !(key.eql? other_key)
						if(keys.has_key? other_key)
							keys[other_key] = keys[other_key]+other_doc[:outbound][key]
						else
							keys[other_key] = other_doc[:outbound][key]
						end
					end
				end
				doc[:inbound] = keys unless keys.empty?
			end
		end

		def calculate_page_rank(reference)
			reference.each do |key, doc|
				rank = 0
				if !doc[:inbound].nil?
					doc[:inbound].each_value{|num| rank+=num}
				end

				doc[:rank] = rank
			end
		end

		def load_cache(tmp_dir)
			reference_data_file = File.join(tmp_dir, 'datacache', @cache_file_name)
			if File.exist? reference_data_file
				return YAML.load_file(reference_data_file)
            end
            return nil
		end

		def store_cache(tmp_dir, reference)
			reference_data_file = File.join(tmp_dir, 'datacache', @cache_file_name)
            FileUtils.mkdir_p File.dirname reference_data_file
            File.open(reference_data_file, 'w') do |out|
              YAML.dump(reference,  out)
            end
		end

		def add_json_api(site, reference)
            json_page = site.engine.load_page( File.join( File.dirname( __FILE__ ), 'json_template.html.haml' ) )
            json_page.output_path = File.join( "api/reference.json" )

            json_page.json = JSON.pretty_generate reference

        	site.pages << json_page
        end
	end
end
end
end


def test()
	rc = Git.open('/home/aslak/dev/source/testing/arquillian.github.com_repos/arquillian-core')
	v = '1.0.0.Final'
	a = 'arquillian-container-test-api'

	ext = Awestruct::Extensions::Reference::JavaDoc.new
	ext.load_all_files(rc, "", a, v) do |content, name|
		if name.match(/.*(RunAsClient).*/)
			doc = OpenStruct.new
			doc.desc = ext.parse_content content
			doc.name = name.match(/([A-Z].*)\.java/)[1]
			doc.package = name.gsub(/\//, '.').gsub(/\.[A-Z].*/, '')

			doc_key = "#{doc[:package]}.#{doc[:name]}"
			puts name
			#puts doc.desc

			reference = Hash.new
			reference[doc_key] = doc

			fake_doc = OpenStruct.new
			fake_doc.desc = ""
			fake_doc.name = "Deployment"
			fake_doc.package = "org.jboss.arquillian.container.test.api"
			fake_doc_key = "#{fake_doc[:package]}.#{fake_doc[:name]}"
			reference[fake_doc_key] = fake_doc

			ext.find_and_create_outbound_links reference

			puts doc[:outbound]
		end
	end
end

#test