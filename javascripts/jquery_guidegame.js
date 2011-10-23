/**
 * A Simple Game
 * 
 */

(function($){

  var VERSION = "1"

  var viewed_action = new Array();
  var completed_action = new Array();
  var greenbar_action = new Array();

  var guides;
  var db;
  var current_guide_id;
  var guide_completed = false;

  $.extend({
    game_init : function(all_guides){
      guides = all_guides;

      db = new localStorageDB('guide_game');
      if(db.isNew()) {
        db.createTable('info', ['version']);
        db.createTable('guides', ['id', 'last_viewed', 'completed', 'bars_completed']);
        db.insert('info', {version: VERSION});
        db.commit();
      }
    },
    game_start : function() {
      completed_guides = db.query('guides', {completed: true})
      for( i = 0; i < viewed_action.length; i++) {
        for( n = 0; n < completed_guides.length; n++) {
          viewed_action[i].apply(completed_guides[n]);
        }
      }

      if(current_guide_id != null) {
        if(db.query('guides', {id: current_guide_id}).length > 0) {
          db.update('guides', {id: current_guide_id}, function(row) {
            row.last_viewed = new Date();

            if(row.completed) {
              guide_completed = true;
            }

            return row;
          });
        }
        else {
          db.insert('guides', {id: current_guide_id, completed: false, bars_completed: 0, last_viewed: new Date()});
        }
        db.commit();
      }

      $(window).scroll(detectGreenBar);
    },    
    game_completed: function() {
      if(guide_completed) {
        return;
      }
      if(current_guide_id == null) {
        throw "Can not complete a guide without having set the current guide";
      }

      db.update('guides', {id: current_guide_id}, function(row) {
        row.completed = true;
        return row;
      });
      db.commit();

      for( i = 0; i < completed_action.length; i++) {
        completed_action[i].call(this, getGuide(current_guide_id), guides);
      }
      guide_completed = true;
    },
    game_greenbar : function(index) {
      if(current_guide_id == null) {
        throw "Can not complete a guide without having set the current guide";
      }
      if(db.query('guides', {id: current_guide_id}).length > 0) {
        if(db.query('guides', {id: current_guide_id})[0].bars_completed >= index) {
          return; // game completed already
        }
      }

      db.update('guides', {id: current_guide_id}, function(row) {
        row.bars_completed = index;
        return row;
      });
      db.commit();

      var guide = getGuide(current_guide_id);
      for( i = 0; i < greenbar_action.length; i++) {
        greenbar_action[i].call(this, guide, index, guides);
      }

      // if all greebar challanges are done, the guide is completed.
      if(guide && guide.bars == index) {
        $.game_completed()
      }
    },
    game_onViewed : function(func) {
      viewed_action.push(func);
    },
    game_onCompleted : function(func) {
      completed_action.push(func);
    },
    game_onGreenBar : function(func) {
      greenbar_action.push(func);
    },
    game_totalGuides : function() {
      return total_guides;
    },
    game_setCurrentGuide : function(current_guide) {
      current_guide_id = current_guide;
    },
    game_is_completed : function() {
      return guide_completed;
    }
  });

  function getGuide(id) {
    for(var i = 0; i < guides.length; i++) {
      if(guides[i].id == current_guide_id) {
        return guides[i]
      }
    }
  }

  function detectGreenBar()
  {
    if($.game_is_completed()) {
      return;
    }
    var docViewTop = $(window).scrollTop();
    var docViewBottom = docViewTop + $(window).height();
    var midView = (docViewBottom - ($(window).height()/2))
    $(".greenbar").each(function(index, elem) {
      var elemTop = elem.offsetTop;
      if(elemTop < midView) {
        $.game_greenbar(index+1);
      }
    });
  }

})(jQuery);
