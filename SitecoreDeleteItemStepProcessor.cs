using Sitecore.DataExchange.Attributes;
using Sitecore.DataExchange.Contexts;
using Sitecore.DataExchange.Extensions;
using Sitecore.DataExchange.Models;
using Sitecore.DataExchange.Plugins;
using Sitecore.DataExchange.Processors.PipelineSteps;
using Sitecore.DataExchange.Providers.Sc.Extensions;
using Sitecore.DataExchange.Repositories;
using Sitecore.Services.Core.Diagnostics;
using Sitecore.Services.Core.Model;
using System;
using System.Collections.Generic;

namespace Feature.DataExchange.Providers.FileSystem
{
    [RequiredEndpointPlugins(new Type[] { typeof(DataLocationSettings), typeof(EndpointSettings), typeof(SitecoreDeleteItemSettings) })]
    public class SitecoreDeleteItemStepProcessor : BasePipelineStepProcessor
    {
        public SitecoreDeleteItemStepProcessor()
        {
        }

        protected override void ProcessPipelineStep(
          PipelineStep pipelineStep,
          PipelineContext pipelineContext,
          ILogger logger)
        {
            SitecoreDeleteItemSettings sitecoreDeleteItemSettings = this.GetSitecoreDeleteItemSettings();
            if (sitecoreDeleteItemSettings == null)
                return;

            IItemModelRepository itemModelRepository = this.GetItemModelRepository();
            if (itemModelRepository == null)
                return;

            IEnumerable<ItemModel> objectAsItemModels = this.GetTargetObjectAsItemModels(pipelineStep, pipelineContext, logger);
            if (objectAsItemModels == null)
                return;

            foreach (ItemModel itemModel in objectAsItemModels)
            {
                var fieldName = sitecoreDeleteItemSettings.Field.GetFieldValue("ItemName").ToString();
                var fieldValue = itemModel.GetFieldValue(fieldName);
                var matchValue = sitecoreDeleteItemSettings.Matches.ToString();
                if(fieldValue.Equals(matchValue))
                {   
                    logger.Info($"Deleting item {itemModel.GetFieldValue("DisplayName")} {itemModel.GetItemId()}. (pipeline step: {pipelineStep.Name}).");
                    itemModelRepository.Delete(itemModel.GetItemId());
                }
            }
        }

        protected virtual SitecoreDeleteItemSettings GetSitecoreDeleteItemSettings()
        {
            SitecoreDeleteItemSettings sitecoreDeleteItemSettings = this.PipelineStep.GetSitecoreDeleteItemSettings();
            if (sitecoreDeleteItemSettings == null)
                return (SitecoreDeleteItemSettings)null;            
            return sitecoreDeleteItemSettings;
        }

        protected virtual IItemModelRepository GetItemModelRepository()
        {
            EndpointSettings endpointSettings = this.PipelineStep.GetEndpointSettings();
            if (endpointSettings == null)
                return (IItemModelRepository)null;
            Endpoint endpointTo = endpointSettings.EndpointTo;
            if (endpointTo == null)
                return (IItemModelRepository)null;            
            return endpointTo.GetItemModelRepositorySettings()?.ItemModelRepository;            
        }        

        protected virtual IEnumerable<ItemModel> GetTargetObjectAsItemModels(
          PipelineStep pipelineStep,
          PipelineContext pipelineContext,
          ILogger logger)
        {
            DataLocationSettings locationSettings = pipelineStep.GetDataLocationSettings();
            object fromPipelineContext = this.GetObjectFromPipelineContext(locationSettings.DataLocation, pipelineContext, logger);
            if (fromPipelineContext == null)
                return (IEnumerable<ItemModel>)null;
            List<ItemModel> objectAsItemModels = new List<ItemModel>();
            if (fromPipelineContext is ItemModel itemModel)
                objectAsItemModels.Add(itemModel);
            else if (fromPipelineContext is IDictionary<string, ItemModel> dictionary)
            {
                foreach (string key in (IEnumerable<string>)dictionary.Keys)
                    objectAsItemModels.Add(dictionary[key]);
            }
            if (objectAsItemModels.Count == 0)
                this.Log(new Action<string>(logger.Error), pipelineContext, "The object from the data source location is not compatible with the pipeline step processor.", new string[1]
                {
          string.Format("data source location: {0}", (object) locationSettings.DataLocation)
                });
            return (IEnumerable<ItemModel>)objectAsItemModels;
        }
    }
}
