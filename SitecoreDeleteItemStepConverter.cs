using Sitecore.Data.Items;
using Sitecore.DataExchange;
using Sitecore.DataExchange.Attributes;
using Sitecore.DataExchange.Converters.PipelineSteps;
using Sitecore.DataExchange.Models;
using Sitecore.DataExchange.Plugins;
using Sitecore.DataExchange.Providers.Sc.Converters.DataAccess.ValueAccessors;
using Sitecore.DataExchange.Providers.Sc.Plugins;
using Sitecore.DataExchange.Repositories;
using Sitecore.Services.Core.Model;

namespace Feature.DataExchange.Providers.FileSystem
{
    [SupportedIds(SitecoreDeleteItemStepTemplateId)]
    public class SitecoreDeleteItemStepConverter : BasePipelineStepConverter
    {
        public const string SitecoreDeleteItemStepTemplateId = "{22863BD8-D746-40F2-9FDD-8D01F49D7E7E}";
        public const string TemplateFieldEndpointTo = "EndpointTo";
        public const string TemplateFieldItemLocation = "ItemLocation";
        public const string TemplateFieldField = "Field";
        public const string TemplateFieldMatches = "Matches";
        public SitecoreDeleteItemStepConverter(IItemModelRepository repository) : base(repository)
        {
        }
        protected override void AddPlugins(ItemModel source, PipelineStep pipelineStep)
        {
            this.AddEndpointSettings(source, pipelineStep);
            this.AddDataLocationSettings(source, pipelineStep);
            this.AddDeleteItemSettings(source, pipelineStep);
            this.AddItemModelRepositorySettings(source, pipelineStep);
        }

        private void AddEndpointSettings(ItemModel source, PipelineStep pipelineStep)
        {
            var settings = new EndpointSettings
            {
                //populate the plugin using values from the item
                EndpointTo = this.ConvertReferenceToModel<Endpoint>(source, TemplateFieldEndpointTo)
            };
            //add the plugin to the pipeline step
            pipelineStep.AddPlugin(settings);
        }

        private void AddDataLocationSettings(ItemModel source, PipelineStep pipelineStep)
        {
            var settings = new DataLocationSettings
            {
                //populate the plugin using values from the item
                DataLocation = this.GetGuidValue(source, TemplateFieldItemLocation)
            };
            //add the plugin to the pipeline step
            pipelineStep.AddPlugin(settings);
        }

        private void AddDeleteItemSettings(ItemModel source, PipelineStep pipelineStep)
        {

            var valueAccessor = this.GetReferenceAsModel(source, TemplateFieldField);
            var templateField = this.GetReferenceAsModel(valueAccessor, TemplateFieldField);

            //create the plugin
            var settings = new SitecoreDeleteItemSettings
            {
                //populate the plugin using values from the item                
                Field = templateField,
                Matches = this.GetStringValue(source, TemplateFieldMatches)
            };
            //add the plugin to the pipeline step
            pipelineStep.AddPlugin(settings);
        }

        private void AddItemModelRepositorySettings(ItemModel source, PipelineStep pipelineStep)
        {
            var settings = new ItemModelRepositorySettings
            {
                ItemModelRepository = Context.ItemModelRepository
            };
            pipelineStep.AddPlugin(settings);
        }
    }
}
